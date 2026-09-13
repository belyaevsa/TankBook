import SwiftUI
import TankbookCore
import UIKit

/// The car tile the vehicle lists and Home's garage card draw: the car's photo
/// when it has one, the glyph otherwise. One view, so a photographed car looks
/// the same in the Garage, the car switcher and on Home (RV.275) - the photo the
/// user added to tell their cars apart is never replaced by an identical glyph.
///
/// The two branches carry different accessibility identifiers
/// (`vehicleTilePhoto` / `vehicleTileGlyph`) so a test can assert WHICH one a
/// given car shows, not merely that a tile exists.
struct VehicleTile: View {
    let photoData: Data?
    /// 42pt is the artboard's list tile; Home's card passes its own size so the
    /// existing frames do not move.
    var size: CGFloat = 42
    var cornerRadius: CGFloat = 11
    var glyph: String = "car.fill"
    var glyphSize: CGFloat = 14

    private var image: UIImage? {
        photoData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityIdentifier("vehicleTilePhoto")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.Palette.midnight)
                    Image(systemName: glyph)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("vehicleTileGlyph")
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
