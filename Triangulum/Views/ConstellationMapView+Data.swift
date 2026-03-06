import Foundation

extension ConstellationMapView {
    enum ConstellationData {
        static let stars: [Star] = [
            // Key bright stars (approximate J2000)
            Star(name: "Sirius", raHours: 6.75, decDeg: -16.716, mag: -1.46),
            Star(name: "Canopus", raHours: 6.4, decDeg: -52.7, mag: -0.72),
            Star(name: "Arcturus", raHours: 14.2667, decDeg: 19.183, mag: -0.05),
            Star(name: "Vega", raHours: 18.6167, decDeg: 38.7837, mag: 0.03),
            Star(name: "Capella", raHours: 5.2667, decDeg: 46.0, mag: 0.08),
            Star(name: "Rigel", raHours: 5.242, decDeg: -8.2017, mag: 0.18),
            Star(name: "Procyon", raHours: 7.655, decDeg: 5.225, mag: 0.38),
            Star(name: "Betelgeuse", raHours: 5.9195, decDeg: 7.407, mag: 0.42),
            Star(name: "Achernar", raHours: 1.65, decDeg: -57.15, mag: 0.46),
            Star(name: "Hadar", raHours: 14.0637, decDeg: -60.373, mag: 0.61),
            Star(name: "Altair", raHours: 19.8464, decDeg: 8.8683, mag: 0.77),
            Star(name: "Aldebaran", raHours: 4.5987, decDeg: 16.509, mag: 0.85),
            Star(name: "Spica", raHours: 13.4199, decDeg: -11.161, mag: 1.04),
            Star(name: "Antares", raHours: 16.4901, decDeg: -26.432, mag: 1.06),
            Star(name: "Pollux", raHours: 7.7553, decDeg: 28.026, mag: 1.14),
            Star(name: "Fomalhaut", raHours: 22.9667, decDeg: -29.6167, mag: 1.16),
            Star(name: "Deneb", raHours: 20.6905, decDeg: 45.2803, mag: 1.25),
            Star(name: "Mimosa", raHours: 12.7953, decDeg: -59.6888, mag: 1.25),
            Star(name: "Regulus", raHours: 10.1395, decDeg: 11.9672, mag: 1.35),
            Star(name: "Castor", raHours: 7.5797, decDeg: 31.8883, mag: 1.58),
            Star(name: "Gacrux", raHours: 12.5194, decDeg: -57.1132, mag: 1.63),
            Star(name: "Bellatrix", raHours: 5.4189, decDeg: 6.3497, mag: 1.64),
            Star(name: "Elnath", raHours: 5.4382, decDeg: 28.6075, mag: 1.65),
            Star(name: "Miaplacidus", raHours: 9.2199, decDeg: -69.7172, mag: 1.67),
            Star(name: "Alnilam", raHours: 5.6036, decDeg: -1.2019, mag: 1.69),
            Star(name: "Alnair", raHours: 22.1372, decDeg: -46.9611, mag: 1.73),
            Star(name: "Alioth", raHours: 12.899, decDeg: 55.961, mag: 1.76),
            Star(name: "Polaris", raHours: 2.5303, decDeg: 89.2641, mag: 1.98),
            Star(name: "Mintaka", raHours: 5.5334, decDeg: -0.2991, mag: 2.23),
            Star(name: "Alnitak", raHours: 5.6793, decDeg: -1.9426, mag: 1.74),
            Star(name: "Saiph", raHours: 5.7959, decDeg: -9.6696, mag: 2.06),
            Star(name: "Dubhe", raHours: 11.0621, decDeg: 61.7508, mag: 1.81),
            Star(name: "Merak", raHours: 11.0307, decDeg: 56.3824, mag: 2.37),
            Star(name: "Phecda", raHours: 11.8972, decDeg: 53.6948, mag: 2.43),
            Star(name: "Megrez", raHours: 12.2571, decDeg: 57.0326, mag: 3.31),
            Star(name: "Mizar", raHours: 13.3988, decDeg: 54.9254, mag: 2.27),
            Star(name: "Alkaid", raHours: 13.7923, decDeg: 49.3133, mag: 1.85)
        ]

        static let moreStars: [Star] = [
            Star(name: "Sadr", raHours: 20.3705, decDeg: 40.2567, mag: 2.23),
            Star(name: "Kochab", raHours: 14.8451, decDeg: 74.1555, mag: 2.08),
            Star(name: "Schedar", raHours: 0.6751, decDeg: 56.5373, mag: 2.24),
            Star(name: "Caph", raHours: 0.1529, decDeg: 59.1498, mag: 2.27),
            Star(name: "Alpheratz", raHours: 0.1398, decDeg: 29.0904, mag: 2.06),
            Star(name: "Mirfak", raHours: 3.4054, decDeg: 49.8612, mag: 1.79),
            Star(name: "Algol", raHours: 3.1361, decDeg: 40.9556, mag: 2.1),
            Star(name: "Denebola", raHours: 11.8177, decDeg: 14.5719, mag: 2.14),
            Star(name: "Markab", raHours: 23.0794, decDeg: 15.2053, mag: 2.49),
            Star(name: "Enif", raHours: 21.7364, decDeg: 9.875, mag: 2.38),
            Star(name: "Rasalhague", raHours: 17.5822, decDeg: 12.5606, mag: 2.08),
            Star(name: "Atria", raHours: 16.8111, decDeg: -69.0278, mag: 1.91),
            Star(name: "Peacock", raHours: 20.4275, decDeg: -56.735, mag: 1.94),
            Star(name: "Alhena", raHours: 6.6285, decDeg: 16.3993, mag: 1.93),
            Star(name: "Bellatrix", raHours: 5.4189, decDeg: 6.3497, mag: 1.64)
        ]

        static let starsExtended: [Star] = {
            var existingNames = Set(stars.map(\.name))
            return stars + moreStars.filter { existingNames.insert($0.name).inserted }
        }()

        // Simple line segments for Orion and Big Dipper
        static let lines: [(String, String)] = [
            // Orion
            ("Betelgeuse", "Bellatrix"),
            ("Betelgeuse", "Alnilam"),
            ("Bellatrix", "Alnilam"),
            ("Alnitak", "Alnilam"),
            ("Alnilam", "Mintaka"),
            ("Rigel", "Saiph"),
            ("Rigel", "Alnitak"),
            ("Saiph", "Mintaka"),
            // Big Dipper (Ursa Major)
            ("Dubhe", "Merak"),
            ("Merak", "Phecda"),
            ("Phecda", "Megrez"),
            ("Megrez", "Alioth"),
            ("Alioth", "Mizar"),
            ("Mizar", "Alkaid")
        ]

        static func star(named name: String) -> Star? {
            stars.first { $0.name == name }
        }
    }
}
