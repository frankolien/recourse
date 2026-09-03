import SwiftUI
import UIKit

struct RecourseScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RecourseGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(RecourseColor.nightText)
        .modifier(RecourseGlassCircle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RecourseGlassCircle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

extension View {
    func recourseGlassCapsule() -> some View {
        modifier(RecourseGlassCapsule())
    }

    /// A field or control that sits on the flat ground and still reads as tappable.
    /// The in-app theme puts content directly on one black; the exception it makes is
    /// for small interactive things, which is exactly what Liquid Glass is for, so on
    /// iOS 26 they become glass and elsewhere they keep the chip fill.
    func recourseGlassField(cornerRadius: CGFloat = 20) -> some View {
        modifier(RecourseGlassField(cornerRadius: cornerRadius))
    }

    /// Groups glass elements so they sample and render as one system rather than as
    /// unrelated panes. No effect before iOS 26.
    ///
    /// `spacing` is how close two glass shapes may come before they merge into a
    /// single shape, so it must stay below the smallest real gap in the layout.
    /// Setting it above one is not a stronger grouping, it deletes a control: a chip
    /// 12 points under a field, in a container spaced 14, is absorbed into the field
    /// and disappears on the next layout pass.
    @ViewBuilder
    func recourseGlassGroup(spacing: CGFloat = 8) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    func recourseGlassBar() -> some View {
        modifier(RecourseGlassBar())
    }

    /// The ground under a bottom action bar, faded rather than cut.
    ///
    /// A hard fill draws a line across the screen and tells you the list ended there.
    /// Fading it lets content pass under the bar, which is what makes a floating action
    /// look like it is floating.
    func recourseBottomFade() -> some View {
        background {
            LinearGradient(
                colors: [RecourseColor.night.opacity(0), RecourseColor.night, RecourseColor.night],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    func recourseKeyboardDismissal() -> some View {
        modifier(RecourseKeyboardDismissal())
    }
}

private struct RecourseKeyboardDismissal: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

private struct RecourseGlassBar: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
    }
}

private struct RecourseGlassField: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(
                    RecourseColor.nightChip,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
    }
}

private struct RecourseGlassCapsule: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.18)), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.34), lineWidth: 1)
                }
        }
    }
}

struct RecoursePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.recourse(15, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RecourseColor.ledger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct RecourseSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.recourse(15, .semibold))
            .foregroundStyle(RecourseColor.nightText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RecourseColor.night, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RecourseColor.nightLine, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
