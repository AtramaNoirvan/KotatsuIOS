import Foundation
import SwiftUI
import UIKit

public enum HttpClientError: LocalizedError {
	case invalidURL(String)
	case httpStatus(Int, String)
	case emptyBody

	public var errorDescription: String? {
		switch self {
		case .invalidURL(let raw):
			return "URL tidak valid: \(raw)"
		case .httpStatus(let code, let url):
			return "HTTP \(code) saat membuka \(url)"
		case .emptyBody:
			return "Respon server kosong"
		}
	}
}

public final class HttpClient {
	public static let shared = HttpClient()

	public static let defaultUserAgent =
		"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

	private let session: URLSession

	private init() {
		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 25
		config.timeoutIntervalForResource = 60
		config.httpCookieAcceptPolicy = .always
		config.httpShouldSetCookies = true
		config.requestCachePolicy = .useProtocolCachePolicy
		config.urlCache = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
		self.session = URLSession(configuration: config)
	}

	public func getData(url urlString: String, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
		guard let url = URL(string: urlString) else {
			throw HttpClientError.invalidURL(urlString)
		}
		var req = URLRequest(url: url)
		req.httpMethod = "GET"
		req.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
		req.setValue("text/html,application/xhtml+xml,application/json,*/*;q=0.8", forHTTPHeaderField: "Accept")
		req.setValue("id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
		for (k, v) in headers {
			req.setValue(v, forHTTPHeaderField: k)
		}
		let (data, response) = try await session.data(for: req)
		guard let http = response as? HTTPURLResponse else {
			throw HttpClientError.emptyBody
		}
		return (data, http)
	}

	public func getString(url urlString: String, headers: [String: String] = [:]) async throws -> String {
		let (data, http) = try await getData(url: urlString, headers: headers)
		guard (200...299).contains(http.statusCode) else {
			throw HttpClientError.httpStatus(http.statusCode, urlString)
		}
		return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
	}

	public func postForm(
		url urlString: String,
		fields: [(String, String)],
		headers: [String: String] = [:]
	) async throws -> String {
		guard let url = URL(string: urlString) else {
			throw HttpClientError.invalidURL(urlString)
		}
		var req = URLRequest(url: url)
		req.httpMethod = "POST"
		req.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
		req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		for (k, v) in headers {
			req.setValue(v, forHTTPHeaderField: k)
		}
		let encoded = fields.map { key, value in
			"\(Self.formEncode(key))=\(Self.formEncode(value))"
		}.joined(separator: "&")
		req.httpBody = encoded.data(using: .utf8)

		let (data, response) = try await session.data(for: req)
		guard let http = response as? HTTPURLResponse else {
			throw HttpClientError.emptyBody
		}
		guard (200...299).contains(http.statusCode) else {
			throw HttpClientError.httpStatus(http.statusCode, urlString)
		}
		return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
	}

	public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
		let (data, response) = try await session.data(for: request)
		guard let http = response as? HTTPURLResponse else {
			throw HttpClientError.emptyBody
		}
		return (data, http)
	}

	public static func formEncode(_ input: String) -> String {
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-._~")
		return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
	}
}

public final class RemoteImageCache {
	public static let shared = RemoteImageCache()
	private let cache = NSCache<NSString, UIImage>()

	private init() {
		cache.countLimit = 120
		cache.totalCostLimit = 80 * 1024 * 1024
	}

	public func image(for key: String) -> UIImage? {
		cache.object(forKey: key as NSString)
	}

	public func set(_ image: UIImage, for key: String) {
		let cost = Int(image.size.width * image.size.height * image.scale * 4)
		cache.setObject(image, forKey: key as NSString, cost: cost)
	}
}

public struct RemoteImageView: View {
	let urlString: String?
	let headers: [String: String]
	let contentMode: SwiftUI.ContentMode

	@State private var uiImage: UIImage?
	@State private var failed = false

	public init(
		urlString: String?,
		headers: [String: String] = [:],
		contentMode: SwiftUI.ContentMode = .fill
	) {
		self.urlString = urlString
		self.headers = headers
		self.contentMode = contentMode
	}

	public var body: some View {
		Group {
			if let uiImage {
				Image(uiImage: uiImage)
					.resizable()
					.aspectRatio(contentMode: contentMode)
			} else if failed {
				ZStack {
					Color.secondary.opacity(0.15)
					Image(systemName: "photo")
						.foregroundStyle(.secondary)
				}
			} else {
				ZStack {
					Color.secondary.opacity(0.12)
					ProgressView()
				}
			}
		}
		.task(id: urlString) {
			await load()
		}
	}

	private func load() async {
		guard let urlString, !urlString.isEmpty else {
			failed = true
			return
		}
		if let cached = RemoteImageCache.shared.image(for: urlString) {
			uiImage = cached
			failed = false
			return
		}
		failed = false
		do {
			let (data, http) = try await HttpClient.shared.getData(url: urlString, headers: headers)
			if (200...299).contains(http.statusCode), let img = UIImage(data: data) {
				RemoteImageCache.shared.set(img, for: urlString)
				uiImage = img
			} else {
				failed = true
			}
		} catch {
			if !Task.isCancelled {
				failed = true
			}
		}
	}
}
