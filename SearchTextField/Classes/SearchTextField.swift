//
//  SearchTextField.swift
//  SearchTextField
//
//  Created by Alejandro Pasccon on 4/20/16.
//  Copyright © 2016 Alejandro Pasccon. All rights reserved.
//

import UIKit

open class SearchTextField: UITextField {
    
    ////////////////////////////////////////////////////////////////////////
    // Public interface
    
    /// Maximum number of results to be shown in the suggestions list
    open var maxNumberOfResults = 0
    
    /// Maximum height of the results list
    open var maxResultsListHeight = 0
    
    /// Indicate if this field has been interacted with yet
    open var interactedWith = false
    
    /// Indicate if keyboard is showing or not
    open var keyboardIsShowing = false

    /// How long to wait before deciding typing has stopped
    open var typingStoppedDelay = 0.8
    
    /// Set your custom visual theme, or just choose between pre-defined SearchTextFieldTheme.lightTheme() and SearchTextFieldTheme.darkTheme() themes
    open var theme = SearchTextFieldTheme.lightTheme() {
        didSet {
            self.tableView?.reloadData()
            
            if let placeholderColor = self.theme.placeholderColor {
                if let placeholderString = self.placeholder {
                    self.attributedPlaceholder = NSAttributedString(string: placeholderString, attributes: [NSAttributedString.Key.foregroundColor: placeholderColor])
                }
                
                self.placeholderLabel?.textColor = placeholderColor
            }
           
            if let hightlightedFont = self.highlightAttributes[.font] as? UIFont {
                self.highlightAttributes[.font] = hightlightedFont.withSize(self.theme.font.pointSize)
            }
        }
    }
    
    /// Show the suggestions list without filter when the text field is focused
    open var startVisible = false
    
    /// Show the suggestions list without filter even if the text field is not focused
    open var startVisibleWithoutInteraction = false {
        didSet {
            if self.startVisibleWithoutInteraction {
                self.textFieldDidChange()
            }
        }
    }
    
    /// Set an array of SearchTextFieldItem's to be used for suggestions
    open func filterItems(_ items: [SearchTextFieldItem]) {
        SearchTextField.currentCellIdentifier = SearchTextField.cellIdentifierItem
        self.filterDataSource = items
    }
    
    /// Set an array of strings to be used for suggestions
    open func filterStrings(_ strings: [String]) {
        SearchTextField.currentCellIdentifier = SearchTextField.cellIdentifierSingleLine
        var items = [SearchTextFieldItem]()
        
        for value in strings {
            items.append(SearchTextFieldItem(title: value))
        }
        
        self.filterDataSource = items
    }
    
    /// Closure to handle when the user pick an item
    open var itemSelectionHandler: SearchTextFieldItemHandler?
    
    /// Closure to handle when the user stops typing
    open var userStoppedTypingHandler: (() -> Void)?
    
    /// Set your custom set of attributes in order to highlight the string found in each item
    open var highlightAttributes: [NSAttributedString.Key: AnyObject] = [.font: UIFont.boldSystemFont(ofSize: 10)]
    
    /// Start showing the default loading indicator, useful for searches that take some time.
    open func showLoadingIndicator() {
        self.rightViewMode = .always
        self.indicator.startAnimating()
    }
    
    /// Force the results list to adapt to RTL languages
    open var forceRightToLeft = false
    
    /// Hide the default loading indicator
    open func stopLoadingIndicator() {
        self.rightViewMode = .never
        self.indicator.stopAnimating()
    }
    
    /// When InlineMode is true, the suggestions appear in the same line than the entered string. It's useful for email domains suggestion for example.
    open var inlineMode: Bool = false {
        didSet {
            if self.inlineMode == true {
                self.autocorrectionType = .no
                self.spellCheckingType = .no
            }
        }
    }
    
    /// Only valid when InlineMode is true. The suggestions appear after typing the provided string (or even better a character like '@')
    open var startFilteringAfter: String?
    
    /// Min number of characters to start filtering
    open var minCharactersNumberToStartFiltering: Int = 0

    /// Force no filtering (display the entire filtered data source)
    open var forceNoFiltering: Bool = false
    
    /// If startFilteringAfter is set, and startSuggestingInmediately is true, the list of suggestions appear inmediately
    open var startSuggestingInmediately = false
    
    /// Allow to decide the comparision options
    open var comparisonOptions: NSString.CompareOptions = [.caseInsensitive]
    
    /// Set the results list's header
    open var resultsListHeader: UIView?

    // Move the table around to customize for your layout
    open var tableXOffset: CGFloat = 0.0
    open var tableYOffset: CGFloat = 0.0
    open var tableCornerRadius: CGFloat = 2.0
    open var tableBottomMargin: CGFloat = 10.0
    
    ////////////////////////////////////////////////////////////////////////
    // Private implementation
    
    fileprivate var tableView: UITableView?
    fileprivate var shadowView: UIView?
    fileprivate var direction: Direction = .down
    fileprivate var fontConversionRate: CGFloat = 0.7
    fileprivate var keyboardFrame: CGRect?
    fileprivate var timer: Timer? = nil
    fileprivate var placeholderLabel: UILabel?
    fileprivate static let cellIdentifierItem = "APSearchTextFieldCell"
    fileprivate static let cellIdentifierSingleLine = "APSearchTextFieldCellSingleLine"
    fileprivate static var currentCellIdentifier: String!
    fileprivate let indicator = UIActivityIndicatorView(style: .gray)
    fileprivate var maxTableViewSize: CGFloat = 0
    
    fileprivate var filteredResults = [SearchTextFieldItem]()
    fileprivate var filterDataSource = [SearchTextFieldItem]() {
        didSet {
            self.filter(forceShowAll: forceNoFiltering)
            self.buildSearchTableView()
            
            if self.startVisibleWithoutInteraction {
                self.textFieldDidChange()
            }
        }
    }
    
    fileprivate var currentInlineItem = ""
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        self.tableView?.removeFromSuperview()
    }
    
    override open func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        
        self.addTarget(self, action: #selector(SearchTextField.textFieldDidChange), for: .editingChanged)
        self.addTarget(self, action: #selector(SearchTextField.textFieldDidBeginEditing), for: .editingDidBegin)
        self.addTarget(self, action: #selector(SearchTextField.textFieldDidEndEditing), for: .editingDidEnd)
        self.addTarget(self, action: #selector(SearchTextField.textFieldDidEndEditingOnExit), for: .editingDidEndOnExit)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SearchTextField.keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SearchTextField.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SearchTextField.keyboardDidChangeFrame(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        
        if self.inlineMode {
            self.buildPlaceholderLabel()
        } else {
            self.buildSearchTableView()
        }
        
        // Create the loading indicator
        self.indicator.hidesWhenStopped = true
        self.rightView = self.indicator
    }
    
    override open func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        var rightFrame = super.rightViewRect(forBounds: bounds)
        rightFrame.origin.x -= 5
        return rightFrame
    }
    
    // Create the filter table and shadow view
    fileprivate func buildSearchTableView() {
        if let tableView = self.tableView, let shadowView = self.shadowView {
            tableView.layer.masksToBounds = true
            tableView.layer.borderWidth = self.theme.borderWidth > 0 ? self.theme.borderWidth : 0.5
            tableView.dataSource = self
            tableView.delegate = self
            tableView.separatorInset = UIEdgeInsets.zero
            tableView.tableHeaderView = self.resultsListHeader
            if self.forceRightToLeft {
                tableView.semanticContentAttribute = .forceRightToLeft
            }
            
            shadowView.backgroundColor = UIColor.lightText
            shadowView.layer.shadowColor = UIColor.black.cgColor
            shadowView.layer.shadowOffset = CGSize.zero
            shadowView.layer.shadowOpacity = 1
            
            self.window?.addSubview(tableView)
        } else {
            self.tableView = UITableView(frame: CGRect.zero)
            self.tableView?.register(UITableViewCell.self, forCellReuseIdentifier: SearchTextField.cellIdentifierItem)
            self.tableView?.register(SingleLineTableViewCell.self, forCellReuseIdentifier: SearchTextField.cellIdentifierSingleLine)
            self.shadowView = UIView(frame: CGRect.zero)
        }
        
        self.redrawSearchTableView()
    }
    
    fileprivate func buildPlaceholderLabel() {
        var newRect = self.placeholderRect(forBounds: self.bounds)
        var caretRect = self.caretRect(for: self.beginningOfDocument)
        let textRect = self.textRect(forBounds: self.bounds)
        
        if let range = textRange(from: self.beginningOfDocument, to: self.endOfDocument) {
            caretRect = self.firstRect(for: range)
        }
        
        newRect.origin.x = caretRect.origin.x + caretRect.size.width + textRect.origin.x
        newRect.size.width = newRect.size.width - newRect.origin.x
        
        if let placeholderLabel = self.placeholderLabel {
            placeholderLabel.font = self.font
            placeholderLabel.frame = newRect
        } else {
            self.placeholderLabel = UILabel(frame: newRect)
            self.placeholderLabel?.font = self.font
            self.placeholderLabel?.backgroundColor = UIColor.clear
            self.placeholderLabel?.lineBreakMode = .byClipping
            
            if let placeholderColor = self.attributedPlaceholder?.attribute(NSAttributedString.Key.foregroundColor, at: 0, effectiveRange: nil) as? UIColor {
                self.placeholderLabel?.textColor = placeholderColor
            } else {
                self.placeholderLabel?.textColor = UIColor ( red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0 )
            }
            
            self.addSubview(self.placeholderLabel!)
        }
    }
    
    // Re-set frames and theme colors
    fileprivate func redrawSearchTableView() {
        if self.inlineMode {
            self.tableView?.isHidden = true
            return
        }
        
        if let tableView = self.tableView {
            guard let frame = self.superview?.convert(self.frame, to: nil) else { return }
            
            //TableViews use estimated cell heights to calculate content size until they
            //  are on-screen. We must set this to the theme cell height to avoid getting an
            //  incorrect contentSize when we have specified non-standard fonts and/or
            //  cellHeights in the theme. We do it here to ensure updates to these settings
            //  are recognized if changed after the tableView is created
            tableView.estimatedRowHeight = self.theme.cellHeight
            if self.direction == .down {
                
                var tableHeight: CGFloat = 0
                if self.keyboardIsShowing, let keyboardHeight = self.keyboardFrame?.size.height {
                    tableHeight = min((tableView.contentSize.height), (UIScreen.main.bounds.size.height - frame.origin.y - frame.height - keyboardHeight))
                } else {
                    tableHeight = min((tableView.contentSize.height), (UIScreen.main.bounds.size.height - frame.origin.y - frame.height))
                }
                
                if maxResultsListHeight > 0 {
                    tableHeight = min(tableHeight, CGFloat(self.maxResultsListHeight))
                }
                
                // Set a bottom margin of 10p
                if tableHeight < tableView.contentSize.height {
                    tableHeight -= self.tableBottomMargin
                }
                
                var tableViewFrame = CGRect(x: 0, y: 0, width: frame.size.width - 4, height: tableHeight)
                tableViewFrame.origin = self.convert(tableViewFrame.origin, to: nil)
                tableViewFrame.origin.x += 2 + self.tableXOffset
                tableViewFrame.origin.y += frame.size.height + 2 + self.tableYOffset
                UIView.animate(withDuration: 0.2, animations: { [weak self] in
                    self?.tableView?.frame = tableViewFrame
                })
                
                var shadowFrame = CGRect(x: 0, y: 0, width: frame.size.width - 6, height: 1)
                shadowFrame.origin = self.convert(shadowFrame.origin, to: nil)
                shadowFrame.origin.x += 3
                shadowFrame.origin.y = tableView.frame.origin.y
                self.shadowView!.frame = shadowFrame
            } else {
                let tableHeight = min((tableView.contentSize.height), (UIScreen.main.bounds.size.height - frame.origin.y - self.theme.cellHeight))
                UIView.animate(withDuration: 0.2, animations: { [weak self] in
                    self?.tableView?.frame = CGRect(x: frame.origin.x + 2, y: (frame.origin.y - tableHeight), width: frame.size.width - 4, height: tableHeight)
                    self?.shadowView?.frame = CGRect(x: frame.origin.x + 3, y: (frame.origin.y + 3), width: frame.size.width - 6, height: 1)
                })
            }
            
            self.superview?.bringSubviewToFront(tableView)
            self.superview?.bringSubviewToFront(self.shadowView!)
            
            if self.isFirstResponder {
                self.superview?.bringSubviewToFront(self)
            }
            
            tableView.layer.borderColor = self.theme.borderColor.cgColor
            tableView.layer.cornerRadius = self.tableCornerRadius
            tableView.separatorColor = self.theme.separatorColor
            tableView.backgroundColor = self.theme.bgColor
            
            tableView.reloadData()
        }
    }
    
    // Handle keyboard events
    @objc open func keyboardWillShow(_ notification: Notification) {
        if !self.keyboardIsShowing && self.isEditing {
            self.keyboardIsShowing = true
            self.keyboardFrame = ((notification as NSNotification).userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            self.interactedWith = true
            self.prepareDrawTableResult()
        }
    }
    
    @objc open func keyboardWillHide(_ notification: Notification) {
        if self.keyboardIsShowing {
            self.keyboardIsShowing = false
            self.direction = .down
            self.redrawSearchTableView()
        }
    }
    
    @objc open func keyboardDidChangeFrame(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.keyboardFrame = ((notification as NSNotification).userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
            self?.prepareDrawTableResult()
        }
    }
    
    @objc open func typingDidStop() {
        self.userStoppedTypingHandler?()
    }
    
    // Handle text field changes
    @objc open func textFieldDidChange() {
        if !self.inlineMode && self.tableView == nil {
            self.buildSearchTableView()
        }
        
        self.interactedWith = true
        
        // Detect pauses while typing
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(timeInterval: typingStoppedDelay, target: self, selector: #selector(SearchTextField.typingDidStop), userInfo: self, repeats: false)
        
        if self.text!.isEmpty {
            self.clearResults()
            self.tableView?.reloadData()
            if self.startVisible || self.startVisibleWithoutInteraction {
                filter(forceShowAll: true)
            }
            self.placeholderLabel?.text = ""
        } else {
            self.filter(forceShowAll: self.forceNoFiltering)
            self.prepareDrawTableResult()
        }
        
        self.buildPlaceholderLabel()
    }
    
    @objc open func textFieldDidBeginEditing() {
        if (self.startVisible || self.startVisibleWithoutInteraction) && self.text!.isEmpty {
            self.clearResults()
            self.filter(forceShowAll: true)
        }
        self.placeholderLabel?.attributedText = nil
    }
    
    @objc open func textFieldDidEndEditing() {
        self.clearResults()
        self.tableView?.reloadData()
        self.placeholderLabel?.attributedText = nil
    }
    
    @objc open func textFieldDidEndEditingOnExit() {
        if let firstElement = self.filteredResults.first {
            if let itemSelectionHandler = self.itemSelectionHandler {
                itemSelectionHandler(self.filteredResults, 0)
            }
            else {
                if self.inlineMode, let filterAfter = self.startFilteringAfter {
                    let stringElements = self.text?.components(separatedBy: filterAfter)
                    
                    self.text = stringElements!.first! + filterAfter + firstElement.title
                } else {
                    self.text = firstElement.title
                }
            }
        }
    }
    
    open func hideResultsList() {
        if let tableFrame:CGRect = self.tableView?.frame {
            let newFrame = CGRect(x: tableFrame.origin.x, y: tableFrame.origin.y, width: tableFrame.size.width, height: 0.0)
            UIView.animate(withDuration: 0.2, animations: { [weak self] in
                self?.tableView?.frame = newFrame
            })
            
        }
    }
    
    fileprivate func filter(forceShowAll addAll: Bool) {
        self.clearResults()
        
        if self.text!.count < self.minCharactersNumberToStartFiltering {
            return
        }
        
        for i in 0 ..< self.filterDataSource.count {
            
            let item = self.filterDataSource[i]
            
            if !self.inlineMode {
                // Find text in title and subtitle
                let titleFilterRange = (item.title as NSString).range(of: self.text!, options: self.comparisonOptions)
                let subtitleFilterRange = item.subtitle != nil ? (item.subtitle! as NSString).range(of: self.text!, options: self.comparisonOptions) : NSMakeRange(NSNotFound, 0)
                
                if titleFilterRange.location != NSNotFound || subtitleFilterRange.location != NSNotFound || addAll {
                    item.attributedTitle = NSMutableAttributedString(string: item.title)
                    item.attributedSubtitle = NSMutableAttributedString(string: (item.subtitle != nil ? item.subtitle! : ""))
                    
                    item.attributedTitle!.setAttributes(self.highlightAttributes, range: titleFilterRange)
                    
                    if subtitleFilterRange.location != NSNotFound {
                        item.attributedSubtitle!.setAttributes(self.highlightAttributesForSubtitle(), range: subtitleFilterRange)
                    }
                    
                    self.filteredResults.append(item)
                }
            } else {
                var textToFilter = self.text!.lowercased()
                
                if self.inlineMode, let filterAfter = self.startFilteringAfter {
                    if let suffixToFilter = textToFilter.components(separatedBy: filterAfter).last, (suffixToFilter != "" || startSuggestingInmediately == true), textToFilter != suffixToFilter {
                        textToFilter = suffixToFilter
                    } else {
                        self.placeholderLabel?.text = ""
                        return
                    }
                }
                
                if item.title.lowercased().hasPrefix(textToFilter) {
                    let indexFrom = textToFilter.index(textToFilter.startIndex, offsetBy: textToFilter.count)
                    let itemSuffix = item.title[indexFrom...]
                    
                    item.attributedTitle = NSMutableAttributedString(string: String(itemSuffix))
                    self.filteredResults.append(item)
                }
            }
        }
        
        self.tableView?.reloadData()
        
        if self.inlineMode {
            self.handleInlineFiltering()
        }
    }
    
    // Clean filtered results
    fileprivate func clearResults() {
        self.filteredResults.removeAll()
        self.tableView?.removeFromSuperview()
    }
    
    // Look for Font attribute, and if it exists, adapt to the subtitle font size
    fileprivate func highlightAttributesForSubtitle() -> [NSAttributedString.Key: AnyObject] {
        var highlightAttributesForSubtitle = [NSAttributedString.Key: AnyObject]()
        
        for attr in self.highlightAttributes {
            if attr.0 == NSAttributedString.Key.font {
                let fontName = (attr.1 as! UIFont).fontName
                let pointSize = (attr.1 as! UIFont).pointSize * fontConversionRate
                highlightAttributesForSubtitle[attr.0] = UIFont(name: fontName, size: pointSize)
            } else {
                highlightAttributesForSubtitle[attr.0] = attr.1
            }
        }
        
        return highlightAttributesForSubtitle
    }
    
    // Handle inline behaviour
    func handleInlineFiltering() {
        if let text = self.text {
            if text == "" {
                self.placeholderLabel?.attributedText = nil
            } else {
                if let firstResult = filteredResults.first {
                    self.placeholderLabel?.attributedText = firstResult.attributedTitle
                } else {
                    self.placeholderLabel?.attributedText = nil
                }
            }
        }
    }
    
    // MARK: - Prepare for draw table result
    
    fileprivate func prepareDrawTableResult() {
        guard let frame = self.superview?.convert(self.frame, to: UIApplication.shared.keyWindow) else { return }
        if let keyboardFrame = self.keyboardFrame {
            var newFrame = frame
            newFrame.size.height += self.theme.cellHeight
            
            if keyboardFrame.intersects(newFrame) {
                self.direction = .up
            } else {
                self.direction = .down
            }
            
            self.redrawSearchTableView()
        } else {
            if self.center.y + self.theme.cellHeight > UIApplication.shared.keyWindow!.frame.size.height {
                self.direction = .up
            } else {
                self.direction = .down
            }
        }
    }
}

extension SearchTextField: UITableViewDelegate, UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView.isHidden = !self.interactedWith || (self.filteredResults.count == 0)
        self.shadowView?.isHidden = !self.interactedWith || (self.filteredResults.count == 0)
        
        if maxNumberOfResults > 0 {
            return min(self.filteredResults.count, maxNumberOfResults)
        } else {
            return self.filteredResults.count
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        var cell: UITableViewCell!
        switch SearchTextField.currentCellIdentifier! {
            case SearchTextField.cellIdentifierSingleLine:
                let singleCell = tableView.dequeueReusableCell(withIdentifier: SearchTextField.cellIdentifierSingleLine, for: indexPath) as! SingleLineTableViewCell
                singleCell.label.font = theme.font
                singleCell.label.textColor = theme.fontColor
                singleCell.label.text = filteredResults[(indexPath as NSIndexPath).row].title
                cell = singleCell
            case SearchTextField.cellIdentifierItem:
                cell = tableView.dequeueReusableCell(withIdentifier: SearchTextField.cellIdentifierItem, for: indexPath)
                cell.textLabel?.font = theme.font
                cell.detailTextLabel?.font = UIFont(name: theme.font.fontName, size: theme.font.pointSize * fontConversionRate)
                cell.textLabel?.textColor = theme.fontColor
                cell.detailTextLabel?.textColor = theme.subtitleFontColor

                cell.textLabel?.text = filteredResults[(indexPath as NSIndexPath).row].title
                cell.detailTextLabel?.text = filteredResults[(indexPath as NSIndexPath).row].subtitle
                cell.textLabel?.attributedText = filteredResults[(indexPath as NSIndexPath).row].attributedTitle
                cell.detailTextLabel?.attributedText = filteredResults[(indexPath as NSIndexPath).row].attributedSubtitle
                cell.imageView?.image = filteredResults[(indexPath as NSIndexPath).row].image
            default:fatalError()
        }

        cell.backgroundColor = UIColor.clear
        cell.layoutMargins = UIEdgeInsets.zero
        cell.preservesSuperviewLayoutMargins = false
        cell.selectionStyle = .none
        
        return cell
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return self.theme.cellHeight
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.itemSelectionHandler == nil {
            self.text = self.filteredResults[(indexPath as NSIndexPath).row].title
        } else {
            let index = indexPath.row
            self.itemSelectionHandler!(filteredResults, index)
        }
        
        self.clearResults()
    }
}

////////////////////////////////////////////////////////////////////////
// Search Text Field Theme

public struct SearchTextFieldTheme {
    public var cellHeight: CGFloat
    public var bgColor: UIColor
    public var borderColor: UIColor
    public var borderWidth : CGFloat = 0
    public var separatorColor: UIColor
    public var font: UIFont
    public var fontColor: UIColor
    public var subtitleFontColor: UIColor
    public var placeholderColor: UIColor?
    
    init(cellHeight: CGFloat, bgColor:UIColor, borderColor: UIColor, separatorColor: UIColor, font: UIFont, fontColor: UIColor, subtitleFontColor: UIColor? = nil) {
        self.cellHeight = cellHeight
        self.borderColor = borderColor
        self.separatorColor = separatorColor
        self.bgColor = bgColor
        self.font = font
        self.fontColor = fontColor
        self.subtitleFontColor = subtitleFontColor ?? fontColor
    }
    
    public static func lightTheme() -> SearchTextFieldTheme {
        return SearchTextFieldTheme(cellHeight: 30, bgColor: UIColor (red: 1, green: 1, blue: 1, alpha: 0.6), borderColor: UIColor (red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0), separatorColor: UIColor.clear, font: UIFont.systemFont(ofSize: 10), fontColor: UIColor.black)
    }
    
    public static func darkTheme() -> SearchTextFieldTheme {
        return SearchTextFieldTheme(cellHeight: 30, bgColor: UIColor (red: 0.8, green: 0.8, blue: 0.8, alpha: 0.6), borderColor: UIColor (red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0), separatorColor: UIColor.clear, font: UIFont.systemFont(ofSize: 10), fontColor: UIColor.white)
    }
}

////////////////////////////////////////////////////////////////////////
// Filter Item

open class SearchTextFieldItem {
    // Private vars
    fileprivate var attributedTitle: NSMutableAttributedString?
    fileprivate var attributedSubtitle: NSMutableAttributedString?
    
    // Public interface
    public var title: String
    public var subtitle: String?
    public var image: UIImage?
    
    public init(title: String, subtitle: String?, image: UIImage?) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
    }
    
    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }
    
    public init(title: String) {
        self.title = title
    }
}

public typealias SearchTextFieldItemHandler = (_ filteredResults: [SearchTextFieldItem], _ index: Int) -> Void

open class SingleLineTableViewCell: UITableViewCell {

    fileprivate let label = UILabel()

    override public init(style: UITableViewCell.CellStyle, reuseIdentifier: String?){
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.configureView()
        self.configureConstraints()
    }

    public required init?(coder aDecoder: NSCoder){
        super.init(coder: aDecoder)
        self.configureView()
        self.configureConstraints()
    }

    fileprivate func configureView(){
        self.contentView.addSubview(self.label)

    }

    fileprivate func configureConstraints(){
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addConstraints([
            NSLayoutConstraint(item: self.label, attribute: .left, relatedBy: .equal, toItem: self.contentView, attribute: .left, multiplier: 1.0, constant: 5),
            NSLayoutConstraint(item: self.label, attribute: .top, relatedBy: .equal, toItem: self.contentView, attribute: .top, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self.label, attribute: .right, relatedBy: .equal, toItem: self.contentView, attribute: .right, multiplier: 1.0, constant: -5),
            NSLayoutConstraint(item: self.label, attribute: .bottom, relatedBy: .equal, toItem: self.contentView, attribute: .bottom, multiplier: 1.0, constant: 0)
            ])
    }
}

////////////////////////////////////////////////////////////////////////
// Suggestions List Direction

enum Direction {
    case down
    case up
}
