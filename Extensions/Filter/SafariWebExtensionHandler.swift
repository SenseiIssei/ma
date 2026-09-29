import Foundation
import SafariServices

/// The content script cannot read the App Group, so it asks here. The
/// answer is the switch board the app wrote in its Reels-Filter screen.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: FilterSettings.load().dictionary]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
