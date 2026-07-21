import SwiftUI

struct GameHUD: View {
    @EnvironmentObject private var game: GameStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GameAssetImage(path: "ui/topbar.svg", contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                hudText("\(game.player.level)", size: 18)
                    .position(x: proxy.size.width * 0.079, y: proxy.size.height * 0.54)

                hudText("\(game.player.energy)/\(game.catalog.rules.energyMax)", size: 13)
                    .position(x: proxy.size.width * 0.345, y: proxy.size.height * 0.51)

                hudText("\(game.player.coins)", size: 14)
                    .position(x: proxy.size.width * 0.69, y: proxy.size.height * 0.51)

                hudText("\(game.player.gems)", size: 14)
                    .position(x: proxy.size.width * 0.89, y: proxy.size.height * 0.51)

                Text(game.levelProgressText)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: proxy.size.width * 0.34, y: proxy.size.height * 0.76)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(game.player.level), \(game.player.energy) Energie, \(game.player.coins) Münzen, \(game.player.gems) Edelsteine")
    }

    private func hudText(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: Color(hex: 0x083F5C), radius: 0, x: 0, y: 1)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }
}

struct OrderStrip: View {
    @EnvironmentObject private var game: GameStore
    let order: OrderDefinition

    private var tutorialFocus: Bool {
        game.activeTutorial?.completion.type == "order_completed"
    }

    var body: some View {
        HStack(spacing: 8) {
            portrait

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("AUFTRAG \(order.sequence)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: 0x80512B))
                    Text(order.dialog)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x4E423A))
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    ForEach(order.requirements, id: \.self) { requirement in
                        RequirementToken(requirement: requirement)
                    }

                    Spacer(minLength: 2)

                    HStack(spacing: 2) {
                        GameAssetImage(path: "board/token_coin.svg")
                            .frame(width: 21, height: 21)
                        Text("\(order.coins)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: 0x80512B))
                    }
                }
            }

            Button { game.completeActiveOrder() } label: {
                VStack(spacing: 2) {
                    Image(systemName: game.canComplete(order) ? "checkmark" : "lock.fill")
                        .font(.system(size: 17, weight: .black))
                    Text("ABGEBEN")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 65, height: 55)
                .background(
                    LinearGradient(
                        colors: game.canComplete(order)
                            ? [Color(hex: 0x70DA51), Color(hex: 0x24A84A)]
                            : [Color(hex: 0xAAB5B8), Color(hex: 0x74868A)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 0, y: 3)
            }
            .buttonStyle(CovePressButtonStyle())
            .disabled(!game.canComplete(order))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFF9E9), Color(hex: 0xFFE2A8)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21)
                .stroke(tutorialFocus ? Color(hex: 0xFFD84D) : .white, lineWidth: tutorialFocus ? 5 : 3)
        )
        .shadow(color: Color(hex: 0x156B83).opacity(0.28), radius: 0, y: 4)
    }

    private var portrait: some View {
        ZStack {
            Circle().fill(Color(hex: 0xBDEFFF))
            Circle().stroke(.white, lineWidth: 3)
            GameAssetImage(path: order.portrait, fallbackSystemName: "person.fill")
                .padding(3)
        }
        .frame(width: 61, height: 61)
        .clipShape(Circle())
    }
}

private struct RequirementToken: View {
    @EnvironmentObject private var game: GameStore
    let requirement: OrderRequirement

    private var owned: Int {
        game.cells.filter { $0.item == requirement.item }.count
    }

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.white.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(hex: 0xD7B36A), lineWidth: 2))
                GameAssetImage(
                    path: game.catalog.items[requirement.item]?.asset ?? "",
                    fallbackSystemName: "shippingbox.fill"
                )
                .padding(3)
                Text("\(requirement.count)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(owned >= requirement.count ? Color(hex: 0x2FAE55) : Color(hex: 0xE65F54), in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 43, height: 43)

            Text("\(min(owned, requirement.count))/\(requirement.count)")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(owned >= requirement.count ? Color(hex: 0x278C48) : Color(hex: 0x745A42))
        }
        .accessibilityLabel("\(requirement.displayName), \(owned) von \(requirement.count)")
    }
}

struct SelectedItemStrip: View {
    @EnvironmentObject private var game: GameStore

    var body: some View {
        HStack(spacing: 8) {
            if let item = game.selectedItem {
                GameAssetImage(path: item.asset, fallbackSystemName: "shippingbox.fill")
                    .frame(width: 43, height: 43)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: 0x61442D))
                    Text("Stufe \(item.stage) · Verkauf \(item.sellValue) Münzen")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x846B55))
                }
                Spacer()
                Button { game.sellSelectedItem() } label: {
                    Label("Verkaufen", systemImage: "tag.fill")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 35)
                        .background(Color(hex: 0xE85F62), in: Capsule())
                }
                .buttonStyle(CovePressButtonStyle())
            } else {
                Image(systemName: "hand.tap.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: 0x177E9C))
                Text("Generator antippen · gleiche Gegenstände zusammenziehen")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x4F6C70))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            if game.canUndo {
                Button { game.undoLastAction() } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(Color(hex: 0x9F66C5))
                }
                .buttonStyle(CovePressButtonStyle())
                .accessibilityLabel("Rückgängig")
            }
        }
        .padding(.horizontal, 10)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white, lineWidth: 2))
    }
}

struct GameNavigationBar: View {
    @EnvironmentObject private var game: GameStore

    var body: some View {
        HStack(spacing: 9) {
            navItem(title: "MERGEN", systemImage: "square.grid.3x3.fill", selected: true) {}
            navItem(title: "STRANDBAR", systemImage: "building.2.fill", selected: false) {
                game.openRestoration()
            }

            Spacer(minLength: 2)

            Button { game.showSettings = true } label: {
                GameAssetImage(path: "ui/btn_settings_normal.svg", fallbackSystemName: "gearshape.fill")
                    .frame(width: 49, height: 49)
            }
            .buttonStyle(CovePressButtonStyle())
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 8)
        .background(Color(hex: 0x0C6684).opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.75), lineWidth: 2))
    }

    private func navItem(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
            }
            .foregroundStyle(selected ? Color(hex: 0xFFE66A) : .white)
            .frame(width: 86, height: 52)
            .background(selected ? .white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(CovePressButtonStyle())
    }
}

struct TutorialCoachmark: View {
    @EnvironmentObject private var game: GameStore
    let step: TutorialStep

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GameAssetImage(path: step.portrait, fallbackSystemName: "person.crop.circle.fill")
                .frame(width: 71, height: 83)
                .clipShape(RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 6) {
                Text(characterName)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xB96A25))
                Text(step.text)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x493B31))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Überspringen") { game.skipTutorial() }
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if game.tutorialAllowsContinue {
                        Button(game.tutorialButtonTitle) { game.advanceTutorial() }
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(Color(hex: 0x28A84B), in: Capsule())
                            .buttonStyle(CovePressButtonStyle())
                    } else {
                        Label(game.tutorialActionHint, systemImage: "hand.point.up.left.fill")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: 0x147F9E))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFFDF3), Color(hex: 0xFFE6B1)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 3))
        .shadow(color: Color(hex: 0x17495A).opacity(0.35), radius: 8, y: 5)
    }

    private var characterName: String {
        ["marina": "MARINA", "kai": "KAI", "gull": "GULL", "shelly": "SHELLY"][step.character] ?? "SUNNY COVE"
    }
}

struct LevelUpOverlay: View {
    @EnvironmentObject private var game: GameStore
    let level: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                GameAssetImage(path: "ui/popup_levelup.svg", fallbackSystemName: "star.circle.fill")
                    .frame(width: 265, height: 210)
                    .overlay(
                        Text("\(level)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: Color(hex: 0xB76B20), radius: 0, y: 3)
                            .offset(y: -28)
                    )
                Text(game.levelUnlockText(for: level))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("WEITER") { game.dismissLevelUp() }
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 49)
                    .background(Color(hex: 0x36B952), in: Capsule())
                    .overlay(Capsule().stroke(.white, lineWidth: 3))
                    .buttonStyle(CovePressButtonStyle())
            }
            .padding(24)
        }
    }
}

struct GameToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(minHeight: 42)
            .background(Color(hex: 0x0E5B73).opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            .padding(.horizontal, 28)
    }
}

struct CampaignCompleteStrip: View {
    var body: some View {
        HStack {
            GameAssetImage(path: "characters/char_marina_excited.svg", fallbackSystemName: "star.fill")
                .frame(width: 64, height: 78)
            VStack(alignment: .leading) {
                Text("KAMPAGNE GESCHAFFT!")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text("Sunny Cove strahlt wieder. Weitere Kapitel folgen mit einem Update.")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
    }
}
