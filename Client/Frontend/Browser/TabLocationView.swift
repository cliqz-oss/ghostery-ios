/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

protocol TabLocationViewDelegate {
    func tabLocationViewDidTapLocation(_ tabLocationView: TabLocationView)
    func tabLocationViewDidLongPressLocation(_ tabLocationView: TabLocationView)
    func tabLocationViewDidTapReaderMode(_ tabLocationView: TabLocationView)
    func tabLocationViewDidTapShield(_ tabLocationView: TabLocationView)
    func tabLocationViewDidTapPageOptions(_ tabLocationView: TabLocationView, from button: UIButton)
    func tabLocationViewDidLongPressPageOptions(_ tabLocationVIew: TabLocationView)
    func tabLocationViewDidBeginDragInteraction(_ tabLocationView: TabLocationView)
    
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    @discardableResult func tabLocationViewDidLongPressReaderMode(_ tabLocationView: TabLocationView) -> Bool
    func tabLocationViewLocationAccessibilityActions(_ tabLocationView: TabLocationView) -> [UIAccessibilityCustomAction]?
}

/* Cliqz: removed private modifier
private struct TabLocationViewUX {
*/
struct TabLocationViewUX {
    static let HostFontColor = UIColor.black
    static let BaseURLFontColor = UIColor.gray
    static let Spacing: CGFloat = 8
    static let StatusIconSize: CGFloat = 18
    static let TPIconSize: CGFloat = 24
    static let ButtonSize: CGFloat = 44
    static let URLBarPadding = 4
}

class TabLocationView: UIView, TabEventHandler {
    var delegate: TabLocationViewDelegate?
    var longPressRecognizer: UILongPressGestureRecognizer!
    var tapRecognizer: UITapGestureRecognizer!
    /* Cliqz: removed private modifier
    private var contentView: UIStackView!
    */
    var contentView: UIStackView!
    private var tabObservers: TabObservers!

    dynamic var baseURLFontColor: UIColor = TabLocationViewUX.BaseURLFontColor {
        didSet { updateTextWithURL() }
    }

    var url: URL? {
        didSet {
            let wasHidden = lockImageView.isHidden
            lockImageView.isHidden = url?.scheme != "https"
            if wasHidden != lockImageView.isHidden {
                UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
            }
            updateTextWithURL()
            pageOptionsButton.isHidden = (url == nil)

            // Cliqz: Update VideoDownloadButton visibility
            updateVideoDownloadButton()

            if url == nil {
                trackingProtectionButton.isHidden = true
            }
            setNeedsUpdateConstraints()
        }
    }

    deinit {
        unregister(tabObservers)
    }

    var readerModeState: ReaderModeState {
        get {
            return readerModeButton.readerModeState
        }
        set (newReaderModeState) {
            //Cliqz: prevent ReaderModeButton from showing on youTube urls
            guard let url = url, !url.isYoutubeURL() else { return }
            
            if newReaderModeState != self.readerModeButton.readerModeState {
                let wasHidden = readerModeButton.isHidden
                self.readerModeButton.readerModeState = newReaderModeState
                readerModeButton.isHidden = (newReaderModeState == ReaderModeState.unavailable)
                separatorLine.isHidden = readerModeButton.isHidden
                if wasHidden != readerModeButton.isHidden {
                    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
                    if !readerModeButton.isHidden {
                        // Delay the Reader Mode accessibility announcement briefly to prevent interruptions.
                        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.ReaderModeAvailableVoiceOverAnnouncement)
                        }
                    }
                }
                UIView.animate(withDuration: 0.1, animations: { () -> Void in
                    self.readerModeButton.alpha = newReaderModeState == .unavailable ? 0 : 1
                })
            }
        }
    }

    lazy var placeholder: NSAttributedString = {
        let placeholderText = NSLocalizedString("Search or enter address", comment: "The text shown in the URL bar on about:home")
        return NSAttributedString(string: placeholderText, attributes: [NSForegroundColorAttributeName: UIColor.gray])
    }()

    lazy var urlTextField: UITextField = {
        let urlTextField = DisplayTextField()

        // Prevent the field from compressing the toolbar buttons on the 4S in landscape.
        urlTextField.setContentCompressionResistancePriority(250, for: .horizontal)
        urlTextField.attributedPlaceholder = self.placeholder
        urlTextField.accessibilityIdentifier = "url"
        urlTextField.accessibilityActionsSource = self
        urlTextField.font = UIConstants.DefaultChromeFont
        urlTextField.backgroundColor = .clear

        // Remove the default drop interaction from the URL text field so that our
        // custom drop interaction on the BVC can accept dropped URLs.
        if #available(iOS 11, *) {
            if let dropInteraction = urlTextField.textDropInteraction {
                urlTextField.removeInteraction(dropInteraction)
            }
        }

        return urlTextField
    }()

    /* Cliqz: removed private modifier
    fileprivate lazy var lockImageView: UIImageView = {
    */
    lazy var lockImageView: UIImageView = {
        let lockImageView = UIImageView(image: UIImage.templateImageNamed("lock_verified"))
        lockImageView.tintColor = UIColor.Defaults.LockGreen
        lockImageView.isAccessibilityElement = true
        lockImageView.contentMode = .center
        lockImageView.accessibilityLabel = NSLocalizedString("Secure connection", comment: "Accessibility label for the lock icon, which is only present if the connection is secure")
        return lockImageView
    }()
    
    lazy var trackingProtectionButton: UIButton = {
        let trackingProtectionButton = UIButton()
        trackingProtectionButton.setImage(UIImage.templateImageNamed("tracking-protection"), for: .normal)
        trackingProtectionButton.addTarget(self, action: #selector(SELDidPressTPShieldButton(_:)), for: .touchUpInside)
        trackingProtectionButton.tintColor = .gray
        trackingProtectionButton.imageView?.contentMode = .scaleAspectFill
        trackingProtectionButton.isHidden = true
        return trackingProtectionButton
    }()
    
    /* Cliqz: removed private modifier
    fileprivate lazy var readerModeButton: ReaderModeButton = {
    */
    lazy var readerModeButton: ReaderModeButton = {
        let readerModeButton = ReaderModeButton(frame: .zero)
        readerModeButton.addTarget(self, action: #selector(SELtapReaderModeButton), for: .touchUpInside)
        readerModeButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(SELlongPressReaderModeButton)))
        readerModeButton.isAccessibilityElement = true
        readerModeButton.isHidden = true
        readerModeButton.imageView?.contentMode = .scaleAspectFit
        readerModeButton.contentHorizontalAlignment = .left
        readerModeButton.accessibilityLabel = NSLocalizedString("Reader View", comment: "Accessibility label for the Reader View button")
        readerModeButton.accessibilityIdentifier = "TabLocationView.readerModeButton"
        readerModeButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: NSLocalizedString("Add to Reading List", comment: "Accessibility label for action adding current page to reading list."), target: self, selector: #selector(SELreaderModeCustomAction))]
        return readerModeButton
    }()
    
    lazy var pageOptionsButton: ToolbarButton = {
        let pageOptionsButton = ToolbarButton(frame: .zero)
        pageOptionsButton.setImage(UIImage.templateImageNamed("menu-More-Options"), for: .normal)
        pageOptionsButton.addTarget(self, action: #selector(SELDidPressPageOptionsButton), for: .touchUpInside)
        pageOptionsButton.isAccessibilityElement = true
        pageOptionsButton.isHidden = true
        pageOptionsButton.imageView?.contentMode = .left
        pageOptionsButton.accessibilityLabel = NSLocalizedString("Page Options Menu", comment: "Accessibility label for the Page Options menu button")
        pageOptionsButton.accessibilityIdentifier = "TabLocationView.pageOptionsButton"
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(SELDidLongPressPageOptionsButton))
        pageOptionsButton.addGestureRecognizer(longPressGesture)
        return pageOptionsButton
    }()
    
    lazy var separatorLine: UIView = {
        let line = UIView()
        line.layer.cornerRadius = 2
        line.isHidden = true
        return line
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.tabObservers = registerFor(.didChangeContentBlocking, queue: .main)

        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(SELlongPressLocation))
        longPressRecognizer.delegate = self

        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(SELtapLocation))
        tapRecognizer.delegate = self

        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(tapRecognizer)

        let spaceView = UIView()
        spaceView.snp.makeConstraints { make in
            make.width.equalTo(TabLocationViewUX.Spacing)
        }
        // The lock and TP icons have custom spacing.
        // TODO: Once we cut ios10 support we can use UIstackview.setCustomSpacing
        let iconStack = UIStackView(arrangedSubviews: [spaceView, lockImageView, trackingProtectionButton])
        iconStack.spacing = TabLocationViewUX.Spacing / 2

        let subviews = [iconStack, urlTextField, readerModeButton, separatorLine, pageOptionsButton]
        contentView = UIStackView(arrangedSubviews: subviews)
        contentView.distribution = .fill
        contentView.alignment = .center
        addSubview(contentView)

        contentView.snp.makeConstraints { make in
            make.edges.equalTo(self)
        }

        lockImageView.snp.makeConstraints { make in
            make.width.equalTo(TabLocationViewUX.StatusIconSize)
            make.height.equalTo(TabLocationViewUX.ButtonSize)
        }
        trackingProtectionButton.snp.makeConstraints { make in
            make.width.equalTo(TabLocationViewUX.TPIconSize)
            make.height.equalTo(TabLocationViewUX.ButtonSize)
        }

        pageOptionsButton.snp.makeConstraints { make in
            make.size.equalTo(TabLocationViewUX.ButtonSize)
        }
        separatorLine.snp.makeConstraints { make in
            make.width.equalTo(1)
            make.height.equalTo(26)
        }
        readerModeButton.snp.makeConstraints { make in
            // The reader mode button only has the padding on one side.
            // The buttons "contentHorizontalAlignment" helps make the button still look centered
            make.size.equalTo(TabLocationViewUX.ButtonSize - 10)
        }

        // Setup UIDragInteraction to handle dragging the location
        // bar for dropping its URL into other apps.
        if #available(iOS 11, *) {
            let dragInteraction = UIDragInteraction(delegate: self)
            dragInteraction.allowsSimultaneousRecognitionDuringLift = true
            self.addInteraction(dragInteraction)
        }
    }

    func tabDidChangeContentBlockerStatus(_ tab: Tab) {
        assertIsMainThread("UI changes must be on the main thread")
        guard #available(iOS 11.0, *), let blocker = tab.contentBlocker as? ContentBlockerHelper else { return }
        switch blocker.status {
        case .Blocking:
            self.trackingProtectionButton.setImage(UIImage.templateImageNamed("tracking-protection"), for: .normal)
            self.trackingProtectionButton.isHidden = false
        case .Disabled, .NoBlockedURLs:
            self.trackingProtectionButton.isHidden = true
        case .Whitelisted:
            self.trackingProtectionButton.setImage(UIImage.templateImageNamed("tracking-protection-off"), for: .normal)
            self.trackingProtectionButton.isHidden = false
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var accessibilityElements: [Any]? {
        get {
            return [lockImageView, urlTextField, readerModeButton, pageOptionsButton].filter { !$0.isHidden }
        }
        set {
            super.accessibilityElements = newValue
        }
    }

    func SELtapReaderModeButton() {
        delegate?.tabLocationViewDidTapReaderMode(self)
    }

    func SELlongPressReaderModeButton(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            delegate?.tabLocationViewDidLongPressReaderMode(self)
        }
    }
    
    func SELDidPressPageOptionsButton(_ button: UIButton) {
        delegate?.tabLocationViewDidTapPageOptions(self, from: button)
    }
    
    func SELDidLongPressPageOptionsButton(_ recognizer: UILongPressGestureRecognizer) {
        delegate?.tabLocationViewDidLongPressPageOptions(self)
    }

    func SELlongPressLocation(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .began {
            delegate?.tabLocationViewDidLongPressLocation(self)
        }
    }

    func SELtapLocation(_ recognizer: UITapGestureRecognizer) {
        delegate?.tabLocationViewDidTapLocation(self)
    }

    func SELDidPressTPShieldButton(_ button: UIButton) {
        delegate?.tabLocationViewDidTapShield(self)
    }

    func SELreaderModeCustomAction() -> Bool {
        return delegate?.tabLocationViewDidLongPressReaderMode(self) ?? false
    }

    fileprivate func updateTextWithURL() {
        if let host = url?.host, AppConstants.MOZ_PUNYCODE {
            urlTextField.text = url?.absoluteString.replacingOccurrences(of: host, with: host.asciiHostToUTF8())
        } else {
            urlTextField.text = url?.absoluteString
        }
        // remove https:// (the scheme) from the url when displaying
        if let scheme = url?.scheme, let range = url?.absoluteString.range(of: "\(scheme)://") {
            urlTextField.text = url?.absoluteString.replacingCharacters(in: range, with: "")
        }
    }
}

extension TabLocationView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // When long pressing a button make sure the textfield's long press gesture is not triggered
        return !(otherGestureRecognizer.view is UIButton)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // If the longPressRecognizer is active, fail the tap recognizer to avoid conflicts.
        return gestureRecognizer == longPressRecognizer && otherGestureRecognizer == tapRecognizer
    }
}

@available(iOS 11.0, *)
extension TabLocationView: UIDragInteractionDelegate {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        // Ensure we actually have a URL in the location bar and that the URL is not local.
        guard let url = self.url, !url.isLocal, let itemProvider = NSItemProvider(contentsOf: url) else {
            return []
        }

        UnifiedTelemetry.recordEvent(category: .action, method: .drag, object: .locationBar)

        let dragItem = UIDragItem(itemProvider: itemProvider)
        return [dragItem]
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        delegate?.tabLocationViewDidBeginDragInteraction(self)
    }
}

extension TabLocationView: AccessibilityActionsSource {
    func accessibilityCustomActionsForView(_ view: UIView) -> [UIAccessibilityCustomAction]? {
        if view === urlTextField {
            return delegate?.tabLocationViewLocationAccessibilityActions(self)
        }
        return nil
    }
}

extension TabLocationView: Themeable {
    func applyTheme(_ theme: Theme) {
        backgroundColor = UIColor.TextField.Background.colorFor(theme)
        urlTextField.textColor = UIColor.Browser.Tint.colorFor(theme)
        readerModeButton.selectedTintColor = UIColor.TextField.ReaderModeButtonSelected.colorFor(theme)
        readerModeButton.unselectedTintColor = UIColor.TextField.ReaderModeButtonUnselected.colorFor(theme)
        
        pageOptionsButton.selectedTintColor = UIColor.TextField.PageOptionsSelected.colorFor(theme)
        pageOptionsButton.unselectedTintColor = UIColor.TextField.PageOptionsUnselected.colorFor(theme)
        pageOptionsButton.tintColor = pageOptionsButton.unselectedTintColor
        separatorLine.backgroundColor = UIColor.TextField.Separator.colorFor(theme)
    }
}

class ReaderModeButton: UIButton {
    var selectedTintColor: UIColor?
    var unselectedTintColor: UIColor?
    override init(frame: CGRect) {
        super.init(frame: frame)
        adjustsImageWhenHighlighted = false
        setImage(UIImage.templateImageNamed("reader"), for: .normal)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isSelected: Bool {
        didSet {
            self.tintColor = (isHighlighted || isSelected) ? selectedTintColor : unselectedTintColor
        }
    }

    override open var isHighlighted: Bool {
        didSet {
            self.tintColor = (isHighlighted || isSelected) ? selectedTintColor : unselectedTintColor
        }
    }

    override var tintColor: UIColor! {
        didSet {
            self.imageView?.tintColor = self.tintColor
        }
    }
    
    var _readerModeState: ReaderModeState = ReaderModeState.unavailable
    
    var readerModeState: ReaderModeState {
        get {
            return _readerModeState
        }
        set (newReaderModeState) {
            _readerModeState = newReaderModeState
            switch _readerModeState {
            case .available:
                self.isEnabled = true
                self.isSelected = false
            case .unavailable:
                self.isEnabled = false
                self.isSelected = false
            case .active:
                self.isEnabled = true
                self.isSelected = true
            }
        }
    }
}

private class DisplayTextField: UITextField {
    weak var accessibilityActionsSource: AccessibilityActionsSource?

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            return accessibilityActionsSource?.accessibilityCustomActionsForView(self)
        }
        set {
            super.accessibilityCustomActions = newValue
        }
    }

    fileprivate override var canBecomeFirstResponder: Bool {
        return false
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: TabLocationViewUX.Spacing, dy: 0)
    }
}
