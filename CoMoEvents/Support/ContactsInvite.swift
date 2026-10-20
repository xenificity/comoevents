import SwiftUI
import ContactsUI
import MessageUI

/// Pick people from Contacts (Apple's picker, no permission prompt) and text them an invite.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: ([String]) -> Void   // phone numbers or emails
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        vc.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0")
        return vc
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        init(onPick: @escaping ([String]) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let targets = contacts.compactMap { c -> String? in
                c.phoneNumbers.first?.value.stringValue ?? c.emailAddresses.first.map { String($0.value) }
            }
            onPick(targets)
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { onPick([]) }
    }
}

/// iMessage/SMS compose sheet with recipients and body prefilled. The user still taps Send.
struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    @Environment(\.dismiss) private var dismiss
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { dismiss() }
    }
}
