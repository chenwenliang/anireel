import SwiftUI

/// Three-page first-launch introduction (D9 story): browse works → tap the centre button to
/// shoot → the first recording is free. Skippable, shown once, requests no permissions.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BrandMark(size: 28, gradient: true)
                Spacer()
                Button("Skip", action: onFinish)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                    .opacity(page == lastPage ? 0 : 1)
                    .disabled(page == lastPage)
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 12)

            TabView(selection: $page) {
                OnboardingPage(
                    title: "Swipe through animated works",
                    message: "Your clips play on the home screen. Until you make one, samples of each style show what's possible."
                ) {
                    HStack(spacing: -28) {
                        ForEach(Array(SampleWork.catalog(for: StyleRegistry.shipping.packs.map(\.descriptor.id)).enumerated()), id: \.element.id) { offset, sample in
                            StyleCover(style: sample.style, cornerRadius: Theme.Radius.medium)
                                .frame(width: 110, height: 196)
                                .rotationEffect(.degrees(Double(offset - 1) * 8))
                                .offset(y: offset == 1 ? -12 : 0)
                                .shadow(color: Theme.Shadow.soft, radius: 12, y: 6)
                                .zIndex(offset == 1 ? 1 : 0)
                        }
                    }
                }
                .tag(0)
                OnboardingPage(
                    title: "Tap the centre button to shoot",
                    message: "Pick a style above the shutter. The camera turns your scene into animation live, and what you see is what gets saved."
                ) {
                    ZStack {
                        Circle().fill(Theme.Gradients.aurora).frame(width: 180, height: 180).opacity(0.18)
                        Circle().fill(Theme.Gradients.mark).frame(width: 104, height: 104)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                            .shadow(color: Theme.Palette.blue.opacity(0.35), radius: 16, y: 8)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .tag(1)
                OnboardingPage(
                    title: "Your first recording is free",
                    message: "No account needed. After that, a free account keeps you recording. Everything stays on your iPhone."
                ) {
                    BrandMark(size: 120, gradient: true)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0...lastPage, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AnyShapeStyle(Theme.Gradients.mark) : AnyShapeStyle(Theme.Palette.hairline))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityHidden(true)

            Button {
                if page < lastPage {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < lastPage ? LocalizedStringKey("Next") : "Get Started")
            }
            .buttonStyle(.gradient)
            .padding(Theme.Spacing.gutter)
        }
        .background(Theme.Palette.surface)
    }
}

private struct OnboardingPage<Art: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            art()
                .frame(height: 220)
                .accessibilityHidden(true)
            Spacer().frame(height: 12)
            Text(title)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
