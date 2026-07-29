import SnapKit
import UIKit

class SelectionCellView: UITableViewCell {
    // MARK: - View Components
    
    private let subtitleLanguage = UILabel().configure {
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: FontUtility.helveticaNeueRegular(ofSize: 12))
        $0.adjustsFontForContentSizeCategory = true
    }

    /// The visual selection indicator.
    ///
    /// Hidden from assistive technology: a "⦁" glyph toggled with `isHidden` is invisible to
    /// VoiceOver, so selection is carried by the cell's `.selected` trait instead and this stays a
    /// purely visual cue.
    private let checkMark = UILabel().configure {
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.text = "\u{2981}"
        $0.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: FontUtility.helveticaNeueRegular(ofSize: 24))
        $0.adjustsFontForContentSizeCategory = true
        $0.isAccessibilityElement = false
    }
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - View Setup
    
    /// Sets up the appearance and layout of the cell's subviews.
    private func setupView() {
        backgroundColor = VideoPlayerColor(palette: .black).uiColor
        contentView.addSubview(subtitleLanguage)
        contentView.addSubview(checkMark)

        subtitleLanguage.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            // A title scaled up for Dynamic Type truncates against the indicator instead of
            // running underneath it. The row's own height is set by the table's delegate, so this
            // view deliberately does not constrain it.
            make.trailing.lessThanOrEqualTo(checkMark.snp.leading).offset(-CGFloat.space8)
        }

        checkMark.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        // The whole row is one VoiceOver element: its label is the title, and its selected state
        // rides on the trait — the only part of "⦁ is showing" that assistive technology can
        // perceive.
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    
    // MARK: - Cell Configuration
    
    /// Configures the cell with the provided title and selection status.
    ///
    /// - Parameters:
    ///   - title: The title to be displayed in the cell.
    ///   - isSelected: A Boolean value indicating whether the cell is selected.
    func configureCell(title: String, isSelected: Bool) {
        subtitleLanguage.text = title
        checkMark.isHidden = !isSelected

        accessibilityLabel = title
        if isSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }
}