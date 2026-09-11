import AppKit
import SwiftUI

struct DetailModalOverlayModifier<Item: Identifiable, ModalContent: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let modalContent: (Item) -> ModalContent

    func body(content: Content) -> some View {
        content
            .overlay {
                if let currentItem = item {
                    ZStack {
                        // Blank space backdrop: clicking anywhere here dismisses the details modal
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    item = nil
                                }
                            }
                            .accessibilityLabel("Dismiss details")
                            .accessibilityHint("Click blank space to return")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("DetailModal.Backdrop")

                        // Centered detail card container
                        modalContent(currentItem)
                            .frame(minWidth: 640, idealWidth: 800, maxWidth: 960, minHeight: 480, idealHeight: 660, maxHeight: 820)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.modal, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.modal, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 28, x: 0, y: 14)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.md)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Absorbs clicks on the card itself so they do not fall through to the backdrop
                            }
                            .accessibilityIdentifier("DetailModal.Card")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(200)
                }
            }
            .onExitCommand {
                if item != nil {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        item = nil
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: item != nil)
    }
}

extension View {
    func detailModalOverlay<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        modifier(DetailModalOverlayModifier(item: item, modalContent: content))
    }
}
