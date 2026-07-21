import Foundation

struct ContentCatalog: Sendable {
    var items: [String: ItemDefinition]
    var generators: [String: GeneratorDefinition]
    var orders: [OrderDefinition]
    var rules: GameRules = .default
    var tutorialSteps: [TutorialStep] = []

    /// Lädt die von Claude gelieferten JSON-Dateien aus dem App-Bundle.
    /// Falls die Dateien beim ersten Prototyp-Build noch nicht eingebunden sind,
    /// bleibt die App dank der eingebauten Fallback-Daten spielbar.
    static func load(bundle: Bundle = .main) -> ContentCatalog {
        let overrideRoot = ContentUpdateStorage.currentURL
        guard let chainsData = data(named: "merge_chains", in: bundle, overrideRoot: overrideRoot),
              let generatorsData = data(named: "generators", in: bundle, overrideRoot: overrideRoot),
              let ordersData = data(named: "orders_campaign_01", in: bundle, overrideRoot: overrideRoot),
              let chains = try? JSONDecoder().decode(ChainFile.self, from: chainsData),
              let generatorFile = try? JSONDecoder().decode(GeneratorFile.self, from: generatorsData),
              let orderFile = try? JSONDecoder().decode(OrderFile.self, from: ordersData),
              chains.chains.count == 5,
              generatorFile.generators.count == 5,
              orderFile.orders.count >= 30 else {
            return bundled()
        }

        var items: [String: ItemDefinition] = [:]
        for chain in chains.chains {
            for stage in chain.stages {
                items[stage.id] = ItemDefinition(id: stage.id, chainID: chain.id,
                    stage: stage.stage, displayName: stage.displayName, asset: stage.asset,
                    sellValue: stage.sellValue, xpValue: stage.xpValue, mergeInto: stage.mergeInto)
            }
        }
        guard items.count == 40 else { return bundled() }

        let generators = Dictionary(uniqueKeysWithValues: generatorFile.generators.map { value in
            (value.id, GeneratorDefinition(id: value.id, displayName: value.displayName,
                chainID: value.producesChain, assetReady: value.states.ready,
                assetUpgraded: value.states.upgraded,
                energyCost: value.base.energyCostPerTap, baseCharges: value.base.maxCharges,
                upgradedCharges: value.upgraded.maxCharges,
                rechargeSeconds: value.base.rechargeSeconds,
                upgradedRechargeSeconds: value.upgraded.rechargeSeconds,
                baseDrops: value.base.dropTable.map { DropEntry(stage: $0.stage, weight: $0.weight) },
                upgradedDrops: value.upgraded.dropTable.map { DropEntry(stage: $0.stage, weight: $0.weight) }))
        })

        let orders = orderFile.orders.map { value in
            OrderDefinition(id: value.id, sequence: value.sequence, character: value.character,
                portrait: value.portrait, dialog: value.dialog,
                requirements: value.requiredItems.map { requirement in
                    OrderRequirement(item: requirement.item, displayName: requirement.displayName,
                        count: requirement.count)
                }, coins: value.rewards.coins ?? 0, gems: value.rewards.gems ?? 0,
                energy: value.rewards.energy ?? 0, xp: value.xp,
                restorationActions: value.restorationActions)
        }
        let rules = (try? JSONDecoder().decode(InitialStateFile.self,
            from: data(named: "initial_game_state", in: bundle, overrideRoot: overrideRoot) ?? Data()))?.rules ?? .default
        let tutorial = (try? JSONDecoder().decode(TutorialFile.self,
            from: data(named: "tutorial_campaign_01", in: bundle, overrideRoot: overrideRoot) ?? Data()))?.stepsAsModels ?? StarterTutorial.make()
        return ContentCatalog(items: items, generators: generators, orders: orders, rules: rules, tutorialSteps: tutorial)
    }

    private static func data(named name: String, in bundle: Bundle, overrideRoot: URL?) -> Data? {
        if let overrideRoot,
           let data = try? Data(contentsOf: overrideRoot.appendingPathComponent("data/\(name).json")) {
            return data
        }
        let locations = [
            bundle.url(forResource: name, withExtension: "json", subdirectory: "GameContent/data"),
            bundle.url(forResource: name, withExtension: "json", subdirectory: "data"),
            bundle.url(forResource: name, withExtension: "json")
        ]
        for location in locations.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: location) { return data }
        }
        return nil
    }

    static func bundled() -> ContentCatalog {
        let chains: [(String, String, [String])] = [
            ("chain_beach", "chain1_beach", ["Muschelsplitter", "Kleine Muschel", "Bunte Muscheln", "Muschelsammlung", "Perlenmuschel", "Perlenkette", "Schmuckschatulle", "Meeresschatzkrone"]),
            ("chain_bar", "chain2_bar", ["Limettenscheibe", "Limetten", "Saftglas", "Limonade", "Kokosdrink", "Tropischer Cocktail", "Cocktailtablett", "Strandbar-Gedeck"]),
            ("chain_surf", "chain3_surf", ["Surf-Wachs", "Wachs & Kamm", "Finne", "Bodyboard", "Einfaches Surfboard", "Profi-Surfboard", "Surf-Ausrüstung", "Legendäres Sunny-Cove-Set"]),
            ("chain_tool", "chain4_tool", ["Schraube", "Schraubenpäckchen", "Schraubendreher", "Hammer", "Werkzeugtasche", "Werkzeugkasten", "Werkbank", "Inselwerkstatt"]),
            ("chain_garden", "chain5_garden", ["Samenkorn", "Keimling", "Kleine Pflanze", "Hibiskus", "Blumenstrauß", "Tropisches Pflanzgefäß", "Dekorative Palme", "Tropischer Gartenbogen"])
        ]
        let suffixes = [
            ["shell_shard", "small_shell", "shell_trio", "shell_collection", "pearl_shell", "pearl_necklace", "jewelry_box", "treasure_crown"],
            ["lime_slice", "limes", "juice_glass", "lemonade", "coconut_drink", "tropical_cocktail", "cocktail_tray", "luxury_bar_set"],
            ["wax", "wax_comb", "fin", "bodyboard", "simple_board", "pro_board", "surf_gear", "legendary_set"],
            ["screw", "screw_pack", "screwdriver", "hammer", "tool_bag", "toolbox", "workbench", "island_workshop"],
            ["seed", "sprout", "small_plant", "hibiscus_pot", "bouquet", "tropical_planter", "palm_pot", "garden_arch"]
        ]
        let values = [2, 5, 12, 30, 75, 180, 450, 1200]
        var items: [String: ItemDefinition] = [:]
        for (chainIndex, chain) in chains.enumerated() {
            for stage in 1...8 {
                let id = "\(chain.1)_\(stage)_\(suffixes[chainIndex][stage - 1])"
                let next = stage < 8 ? "\(chain.1)_\(stage + 1)_\(suffixes[chainIndex][stage])" : nil
                items[id] = ItemDefinition(id: id, chainID: chain.0, stage: stage,
                    displayName: chain.2[stage - 1], asset: "items/\(id).svg",
                    sellValue: values[stage - 1], xpValue: max(1, 1 << (stage - 1)), mergeInto: next)
            }
        }
        let generatorSeed: [(String, String, String)] = [
            ("gen1_beach_crate", "Angeschwemmte Strandkiste", "chain_beach"),
            ("gen2_bar_cart", "Strandbar-Wagen", "chain_bar"),
            ("gen3_surf_locker", "Surf-Spind", "chain_surf"),
            ("gen4_tool_chest", "Alte Werkzeugkiste", "chain_tool"),
            ("gen5_garden_basket", "Gartenkorb", "chain_garden")
        ]
        var generators: [String: GeneratorDefinition] = [:]
        for seed in generatorSeed {
            generators[seed.0] = GeneratorDefinition(id: seed.0, displayName: seed.1,
                chainID: seed.2, assetReady: "generators/\(seed.0)_ready.svg",
                assetUpgraded: "generators/\(seed.0)_upgraded.svg", energyCost: 1,
                baseCharges: 8, upgradedCharges: 12, rechargeSeconds: 120,
                upgradedRechargeSeconds: 90,
                baseDrops: [.init(stage: 1, weight: 0.55), .init(stage: 2, weight: 0.32), .init(stage: 3, weight: 0.13)],
                upgradedDrops: [.init(stage: 1, weight: 0.4), .init(stage: 2, weight: 0.35), .init(stage: 3, weight: 0.2), .init(stage: 4, weight: 0.05)])
        }
        return ContentCatalog(items: items, generators: generators, orders: StarterOrders.make(), tutorialSteps: StarterTutorial.make())
    }
}

private struct ChainFile: Decodable {
    let chains: [Chain]
    struct Chain: Decodable {
        let id: String
        let stages: [Stage]
    }
    struct Stage: Decodable {
        let stage: Int
        let id: String
        let asset: String
        let displayName: String
        let sellValue: Int
        let xpValue: Int
        let mergeInto: String?
    }
}

private struct GeneratorFile: Decodable {
    let generators: [Generator]
    struct Generator: Decodable {
        let id: String
        let displayName: String
        let producesChain: String
        let states: States
        let base: Balance
        let upgraded: Balance
    }
    struct States: Decodable { let ready: String; let upgraded: String }
    struct Balance: Decodable {
        let energyCostPerTap: Int
        let maxCharges: Int
        let rechargeSeconds: TimeInterval
        let dropTable: [Drop]
    }
    struct Drop: Decodable { let stage: Int; let weight: Double }
}

private struct OrderFile: Decodable {
    let orders: [Order]
    struct Order: Decodable {
        let id: String
        let sequence: Int
        let character: String
        let portrait: String
        let dialog: String
        let requiredItems: [Requirement]
        let rewards: Rewards
        let xp: Int
        let restorationActions: [String]
    }
    struct Requirement: Decodable {
        let item: String
        let displayName: String
        let count: Int
    }
    struct Rewards: Decodable {
        let coins: Int?
        let gems: Int?
        let energy: Int?
    }
}

private struct InitialStateFile: Decodable {
    let config: Config

    struct Config: Decodable {
        let energy: Energy
        let generators: Generators
        let levels: Levels
        let currency: Currency
        let clearing: Clearing
    }
    struct Energy: Decodable {
        let max: Int
        let start: Int
        let regenSeconds: TimeInterval
        let levelUpRefill: Bool
        let rewardsMayOverfill: Bool
    }
    struct Generators: Decodable { let autoUpgradeAfterProduced: Int }
    struct Levels: Decodable {
        let thresholds: [Int]
        let rewardGemsPerLevel: Int
        let energyRefillOnLevelUp: Bool
        let unlockRowAtLevel: [String: Int]
    }
    struct Currency: Decodable { let startCoins: Int; let startGems: Int }
    struct Clearing: Decodable { let sandCoinsPerLayer: Int; let cobwebCoins: Int }

    var rules: GameRules {
        GameRules(energyMax: config.energy.max, energyStart: config.energy.start,
            startCoins: config.currency.startCoins, startGems: config.currency.startGems,
            energyRegenSeconds: config.energy.regenSeconds,
            autoUpgradeAfterProduced: config.generators.autoUpgradeAfterProduced,
            levelThresholds: config.levels.thresholds,
            rewardGemsPerLevel: config.levels.rewardGemsPerLevel,
            energyRefillOnLevelUp: config.levels.energyRefillOnLevelUp,
            rewardsMayOverfillEnergy: config.energy.rewardsMayOverfill,
            unlockRowAtLevel: Dictionary(uniqueKeysWithValues: config.levels.unlockRowAtLevel.compactMap { key, value in
                Int(key).map { ($0, value) }
            }), sandCoinsPerLayer: config.clearing.sandCoinsPerLayer,
            cobwebCoins: config.clearing.cobwebCoins)
    }
}

private struct TutorialFile: Decodable {
    let steps: [Step]
    struct Step: Decodable {
        let id: String
        let character: String
        let portrait: String
        let text: String
    }
    var stepsAsModels: [TutorialStep] {
        steps.map { TutorialStep(id: $0.id, character: $0.character, portrait: $0.portrait, text: $0.text) }
    }
}

private enum StarterOrders {
    static func make() -> [OrderDefinition] {
        let raw: [(String, String, [(String, Int)], Int, Int, Int, Int, [String])] = [
            ("gull", "Willkommen zurück in Sunny Cove! Sammle ein paar Muscheln, dann legen wir los.", [("chain1_beach_2_small_shell", 2)], 40, 0, 0, 10, []),
            ("marina", "Räumen wir zuerst den Strand auf.", [("chain1_beach_2_small_shell", 3)], 55, 0, 0, 12, []),
            ("kai", "Für die Bar brauchen wir frische Limetten.", [("chain2_bar_2_limes", 2)], 70, 0, 5, 14, []),
            ("gull", "Ohne Werkzeug wird das nichts.", [("chain4_tool_1_screw", 3)], 80, 0, 0, 16, []),
            ("marina", "Ein frischer Saft hilft beim Denken.", [("chain2_bar_3_juice_glass", 1)], 90, 1, 0, 18, []),
            ("kai", "Die alte Theke lässt sich retten!", [("chain4_tool_3_screwdriver", 1)], 120, 0, 10, 22, ["unlock_element:elem_counter"]),
            ("shelly", "Für meinen Garten brauche ich ein Samenkorn.", [("chain5_garden_1_seed", 3)], 110, 0, 0, 20, []),
            ("marina", "Bunte Muscheln wären eine schöne Dekoration.", [("chain1_beach_3_shell_trio", 2)], 140, 0, 0, 24, []),
            ("kai", "Zeit fürs Dach! Mit einem Hammer kriegen wir das Gerüst hoch.", [("chain4_tool_4_hammer", 1), ("chain1_beach_3_shell_trio", 1)], 180, 2, 15, 40, ["set_state:partial", "unlock_element:elem_roof"]),
            ("gull", "Ein kühler Kokosdrink zur Feier?", [("chain2_bar_5_coconut_drink", 1)], 160, 0, 0, 28, []),
            ("marina", "Eine kleine Muschelsammlung für die Wand.", [("chain1_beach_4_shell_collection", 1)], 190, 0, 10, 32, []),
            ("kai", "Das Schild muss wieder ran, damit man uns findet!", [("chain4_tool_5_tool_bag", 1), ("chain2_bar_4_lemonade", 1)], 220, 1, 0, 38, ["unlock_element:elem_sign"]),
            ("shelly", "Meine erste Pflanze wächst!", [("chain5_garden_3_small_plant", 2)], 200, 0, 0, 34, []),
            ("marina", "Die Surfer fragen schon. Hast du Surf-Wachs?", [("chain3_surf_2_wax_comb", 2)], 210, 0, 15, 36, []),
            ("kai", "Setz dich – nachdem du einen Barhocker herbeigeschafft hast.", [("chain4_tool_5_tool_bag", 1), ("chain5_garden_3_small_plant", 1)], 240, 2, 0, 42, ["unlock_element:elem_chair_a"]),
            ("gull", "Ein echter Cocktail wertet die Bar auf.", [("chain2_bar_6_tropical_cocktail", 1)], 260, 0, 0, 44, []),
            ("marina", "Noch ein Hocker, dann können zwei Gäste anstoßen.", [("chain4_tool_6_toolbox", 1), ("chain2_bar_5_coconut_drink", 1)], 300, 3, 20, 50, ["unlock_element:elem_chair_b"]),
            ("shelly", "Oh! Ein Hibiskus im Topf – genau der fehlt.", [("chain5_garden_4_hibiscus_pot", 1)], 280, 0, 0, 46, []),
            ("kai", "Für die Abende brauchen wir Licht.", [("chain3_surf_5_simple_board", 1)], 320, 0, 0, 48, []),
            ("marina", "Lichterkette anbringen!", [("chain4_tool_6_toolbox", 1), ("chain2_bar_6_tropical_cocktail", 1)], 360, 3, 25, 60, ["unlock_element:elem_string_lights"]),
            ("gull", "Die Gäste lieben Blumen.", [("chain5_garden_5_bouquet", 1)], 340, 0, 0, 52, []),
            ("shelly", "Mein Pflanzgefäß ist fertig bepflanzt.", [("chain5_garden_6_tropical_planter", 1), ("chain1_beach_4_shell_collection", 1)], 380, 1, 0, 56, []),
            ("marina", "Frische Blumen an die Theke!", [("chain5_garden_5_bouquet", 2)], 420, 2, 20, 64, ["unlock_element:elem_flowers"]),
            ("kai", "Ein Profi-Surfboard als Deko zieht die Surfer an.", [("chain3_surf_6_pro_board", 1)], 460, 0, 0, 66, []),
            ("gull", "Für die große Eröffnung: ein Cocktailtablett.", [("chain2_bar_7_cocktail_tray", 1)], 500, 3, 30, 72, []),
            ("marina", "Häng das Surfbrett als Deko auf!", [("chain3_surf_6_pro_board", 1), ("chain4_tool_7_workbench", 1)], 560, 3, 0, 80, ["unlock_element:elem_surfboard_deco"]),
            ("shelly", "Fast geschafft! Meine dekorative Palme wartet.", [("chain5_garden_7_palm_pot", 1)], 600, 2, 25, 84, []),
            ("marina", "Zeit für die letzte Palme – dann ist die Strandbar zurück!", [("chain5_garden_7_palm_pot", 1), ("chain4_tool_7_workbench", 1)], 900, 5, 40, 120, ["set_state:restored", "unlock_element:elem_palm"]),
            ("kai", "Grande Opening! Ein legendäres Surf-Set als Blickfang.", [("chain3_surf_8_legendary_set", 1)], 1200, 4, 0, 140, []),
            ("gull", "Sunny Cove erstrahlt wieder. Krön den Tag mit einem Strandbar-Gedeck!", [("chain2_bar_8_luxury_bar_set", 1), ("chain1_beach_6_pearl_necklace", 1)], 2000, 8, 50, 300, [])
        ]
        return raw.enumerated().map { index, value in
            let requirements = value.2.map { OrderRequirement(item: $0.0, displayName: $0.0, count: $0.1) }
            return OrderDefinition(id: String(format: "order_%02d", index + 1), sequence: index + 1,
                character: value.0, portrait: "characters/char_\(value.0)_friendly.svg", dialog: value.1,
                requirements: requirements, coins: value.3, gems: value.4, energy: value.5,
                xp: value.6, restorationActions: value.7)
        }
    }
}

private enum StarterTutorial {
    static func make() -> [TutorialStep] {
        [
            TutorialStep(id: "tut_01", character: "gull", portrait: "characters/char_gull_happy.svg", text: "Der Sturm hat Omas Strandbar zugerichtet. Zusammen bauen wir Sunny Cove wieder auf."),
            TutorialStep(id: "tut_02", character: "kai", portrait: "characters/char_kai_pointing.svg", text: "Tipp eine Generator-Kiste an. Sie liefert dir die ersten Fundstücke."),
            TutorialStep(id: "tut_03", character: "marina", portrait: "characters/char_marina_friendly.svg", text: "Zwei gleiche Gegenstände ergeben durch Zusammenführen eine bessere Stufe.")
        ]
    }
}
}
