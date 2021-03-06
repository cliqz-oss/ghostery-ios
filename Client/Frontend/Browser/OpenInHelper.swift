/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import MobileCoreServices
import PassKit
import WebKit
import Shared

struct MIMEType {
    static let Bitmap = "image/bmp"
    static let CSS = "text/css"
    static let GIF = "image/gif"
    static let JavaScript = "text/javascript"
    static let JPEG = "image/jpeg"
    static let HTML = "text/html"
    static let OctetStream = "application/octet-stream"
    static let Passbook = "application/vnd.apple.pkpass"
    static let PDF = "application/pdf"
    static let PlainText = "text/plain"
    static let PNG = "image/png"
    static let WebP = "image/webp"
    static let Calendar = "text/calendar"

    private static let webViewViewableTypes: [String] = [MIMEType.Bitmap, MIMEType.GIF, MIMEType.JPEG, MIMEType.HTML, MIMEType.PDF, MIMEType.PlainText, MIMEType.PNG, MIMEType.WebP]

    static func canShowInWebView(_ mimeType: String) -> Bool {
        return webViewViewableTypes.contains(mimeType.lowercased())
    }

    static func mimeTypeFromFileExtension(_ fileExtension: String) -> String {
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)?.takeRetainedValue(), let mimeType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
            return mimeType as String
        }

        return MIMEType.OctetStream
    }
}

protocol OpenInHelper {
    init?(request: URLRequest?, response: URLResponse, canShowInWebView: Bool, forceDownload: Bool, browserViewController: BrowserViewController)
    func open()
}

class DownloadHelper: NSObject, OpenInHelper {
    fileprivate let request: URLRequest
    fileprivate let preflightResponse: URLResponse
    fileprivate let browserViewController: BrowserViewController

    required init?(request: URLRequest?, response: URLResponse, canShowInWebView: Bool, forceDownload: Bool, browserViewController: BrowserViewController) {
        guard let request = request else {
            return nil
        }

        let mimeType = response.mimeType ?? MIMEType.OctetStream
        let isAttachment = mimeType == MIMEType.OctetStream

        // Bug 1474339 - Don't auto-download files served with 'Content-Disposition: attachment'
        // Leaving this here for now, but commented out. Checking this HTTP header is
        // what Desktop does should we ever decide to change our minds on this.
        // let contentDisposition = (response as? HTTPURLResponse)?.allHeaderFields["Content-Disposition"] as? String
        // let isAttachment = contentDisposition?.starts(with: "attachment") ?? (mimeType == MIMEType.OctetStream)

        guard isAttachment || !canShowInWebView || forceDownload else {
            return nil
        }

        self.request = request
        self.preflightResponse = response
        self.browserViewController = browserViewController
    }

    func open() {
        guard let host = request.url?.host else {
            return
        }

        let download = Download(preflightResponse: preflightResponse, request: request)

        let expectedSize = download.totalBytesExpected != nil ? ByteCountFormatter.string(fromByteCount: download.totalBytesExpected!, countStyle: .file) : nil

        let filenameItem: PhotonActionSheetItem
        if let expectedSize = expectedSize {
            let expectedSizeAndHost = "\(expectedSize) — \(host)"
            filenameItem = PhotonActionSheetItem(title: download.filename, text: expectedSizeAndHost, iconString: "file", iconAlignment: .right, bold: true)
        } else {
            filenameItem = PhotonActionSheetItem(title: download.filename, text: host, iconString: "file", iconAlignment: .right, bold: true)
        }

        let downloadFileItem = PhotonActionSheetItem(title: Strings.OpenInDownloadHelperAlertDownloadNow, iconString: "download") { _ in
            self.browserViewController.downloadQueue.enqueueDownload(download)
            UnifiedTelemetry.recordEvent(category: .action, method: .tap, object: .downloadNowButton)
        }

        let actions = [[filenameItem], [downloadFileItem]]

        browserViewController.presentSheetWith(actions: actions, on: browserViewController, from: browserViewController.urlBar, closeButtonTitle: Strings.CancelString, suppressPopover: true)
    }
}

class OpenPassBookHelper: NSObject, OpenInHelper {
    fileprivate var url: URL

    fileprivate let browserViewController: BrowserViewController

    required init?(request: URLRequest?, response: URLResponse, canShowInWebView: Bool, forceDownload: Bool, browserViewController: BrowserViewController) {
        guard let mimeType = response.mimeType, mimeType == MIMEType.Passbook, PKAddPassesViewController.canAddPasses(),
            let responseURL = response.url, !forceDownload else { return nil }
        self.url = responseURL
        self.browserViewController = browserViewController
        super.init()
    }

    func open() {
        guard let passData = try? Data(contentsOf: url) else { return }
        var error: NSError? = nil
        let pass = PKPass(data: passData, error: &error)
        if let _ = error {
            // display an error
            let alertController = UIAlertController(
                title: Strings.UnableToAddPassErrorTitle,
                message: Strings.UnableToAddPassErrorMessage,
                preferredStyle: .alert)
            alertController.addAction(
                UIAlertAction(title: Strings.UnableToAddPassErrorDismiss, style: .cancel) { (action) in
                    // Do nothing.
                })
            browserViewController.present(alertController, animated: true, completion: nil)
            return
        }
        let passLibrary = PKPassLibrary()
        if passLibrary.containsPass(pass) {
            UIApplication.shared.open(pass.passURL!, options: [:])
        } else {
            let addController = PKAddPassesViewController(pass: pass)
            browserViewController.present(addController, animated: true, completion: nil)
        }
    }
}
