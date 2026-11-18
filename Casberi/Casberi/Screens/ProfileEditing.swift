import SwiftUI
import PhotosUI

/// **ONE QUESTION FOR WHO YOU ARE (prd §1835, §1860).** The name and the
/// photo are one row in Settings and one face on Account's box, and both
/// ask the same thing on a tap: Add name or Change name, Add photo or Change
/// photo, Remove photo once there is one. One modifier, so the two doors
/// can never ask it differently.
///
/// The name is an alert rather than a tray: the address-book rename's exact
/// shape, for the same reason — one short string, typed once, with nothing
/// else on the screen to decide. Remove exists only once there is something
/// to remove (§83: a control that can't do anything isn't offered).
struct ProfileEditing: ViewModifier {
    @Binding var isPresented: Bool
    @State private var pickerOpen = false
    @State private var selection: PhotosPickerItem?
    @State private var nameEditorOpen = false
    @State private var nameDraft = ""

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $pickerOpen, selection: $selection, matching: .images)
            .confirmationDialog("Name", isPresented: $isPresented, titleVisibility: .hidden) {
                Button(ProfileStore.shared.name == nil ? "Add name" : "Change name") {
                    // The draft opens on what's stored, so Save on an
                    // untouched field is a no-op rather than a wipe.
                    nameDraft = ProfileStore.shared.name ?? ""
                    nameEditorOpen = true
                }
                Button(ProfileStore.shared.avatar == nil ? "Add photo" : "Change photo") { pickerOpen = true }
                if ProfileStore.shared.avatar != nil {
                    Button("Remove photo", role: .destructive) {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ProfileStore.shared.avatar = nil }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Your name", isPresented: $nameEditorOpen) {
                TextField(String(localized: "Name"), text: $nameDraft)
                    .textInputAutocapitalization(.words)
                    .textContentType(.givenName)
                Button(String(localized: "Save")) {
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) {
                        ProfileStore.shared.name = ProfileStore.preparedName(nameDraft)
                    }
                }
                if ProfileStore.shared.name != nil {
                    Button(String(localized: "Remove"), role: .destructive) {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ProfileStore.shared.name = nil }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                // The honest fact, where it's asked for rather than in a
                // privacy screen nobody opens while typing.
                Text("Only used to greet you. It stays on \(DS.device).")
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        ProfileStore.shared.avatar = ProfileStore.prepared(image)
                    }
                    selection = nil
                }
            }
    }
}

extension View {
    /// Raises the name-and-photo question while `isPresented` holds.
    func profileEditing(isPresented: Binding<Bool>) -> some View {
        modifier(ProfileEditing(isPresented: isPresented))
    }
}
