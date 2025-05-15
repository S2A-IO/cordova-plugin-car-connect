//  ImageCacheProvider.swift
//  Created for CarConnect (iOS CarPlay)

import Foundation
import UIKit

/// Lightweight image-fetcher + (memory + disk) cache.
///
/// * Always calls `completion` on the main thread.
/// * Never blocks - downloads run on a background queue.
/// * Files are stored in <App-Caches>/CarConnectImages/.
final class ImageCacheProvider {

    // MARK: – Public

    static let shared = ImageCacheProvider()

    /// Fetches (or returns cached) image for the given URL.
    /// - Parameter completion: Receives nil on error.
    func fetch(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        // 1. Memory cache first
        if let img = memory.object(forKey: url as NSURL) {
            return completion(img)
        }

        // 2. Disk cache next
        io.async {
            if
                let fileURL = self.diskURL(for: url),
                let data    = try? Data(contentsOf: fileURL),
                let img     = UIImage(data: data)
            {
                self.memory.setObject(img, forKey: url as NSURL)
                return DispatchQueue.main.async { completion(img) }
            }

            // 3. Download
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard
                    let data  = data,
                    let image = UIImage(data: data)
                else {
                    return DispatchQueue.main.async { completion(nil) }
                }

                // save to caches
                self.memory.setObject(image, forKey: url as NSURL)
                self.io.async {
                    if let fileURL = self.diskURL(for: url) {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
                DispatchQueue.main.async { completion(image) }
            }.resume()
        }
    }

    // MARK: – Private

    private let memory = NSCache<NSURL, UIImage>()
    private let io     = DispatchQueue(label: "CarConnect.ImageCache")  // serial

    private func diskURL(for url: URL) -> URL? {
        guard
            let caches = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first
        else { return nil }
        let dir = caches.appendingPathComponent("CarConnectImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent(url.lastPathComponent)
    }

    private init() { }
}
