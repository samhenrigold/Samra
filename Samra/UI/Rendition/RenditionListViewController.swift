//
//  RenditionListViewController.swift
//  Samra
//
//  Created by Serena on 18/02/2023.
// 

import Cocoa
import class SwiftUI.NSHostingController
import AssetCatalogWrapper
import AppKitPrivates

/// A View Controller displaying all the renditions of a given Asset Catalog.
class RenditionListViewController: NSViewController {
    
    static let titleHeaderIdentifier = "Identifier"
    
    typealias DataSource = NSCollectionViewDiffableDataSource<RenditionType, Rendition>
    var dataSource: DataSource!
    var collectionView: CollectionViewWithMenu!
    lazy var allItemsSnapshot = addSnapshot(collectionToAdd: collection)
    
    var itemToDeleteIndexPath: IndexPath? = nil
    
    var catalog: CUICatalog
    var collection: RenditionCollection
    let fileURL: URL
    
    init(catalog: CUICatalog, collection: RenditionCollection, fileURL: URL) {
        self.catalog = catalog
        self.collection = collection
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }
    
    var splitViewParent: CollapseNotifierSplitViewController? {
        parent as? CollapseNotifierSplitViewController
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        collectionView = CollectionViewWithMenu()
        
        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, rendition in
            let cell = collectionView.makeItem(withIdentifier: RenditionCollectionViewItem.reuseIdentifier,
                                               for: indexPath) as! RenditionCollectionViewItem
            cell.configure(rendition: rendition)
            return cell
        }
        
#warning("Add footers for explanations for multisizeImageSet")
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == NSCollectionView.elementKindSectionHeader else {
                return nil
            }
            
            let header = collectionView.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: RenditionTypeHeaderView.identifier,
                for: indexPath) as! RenditionTypeHeaderView
            let snapshot = self.dataSource.snapshot()
            let section = snapshot.sectionIdentifiers[indexPath.section]
            header.configure(with: section, numberOfItems: snapshot.numberOfItems(inSection: section))
            return header
        }
        
        collectionView.allowsMultipleSelection = false
        collectionView.isSelectable = true
        collectionView.delegate = self
        collectionView.menuProvider = self
        collectionView.collectionViewLayout = makeLayout(layout: .horizontal)
        collectionView.identifier = "HorizLayout"
        
        collectionView.register(RenditionCollectionViewItem.self,
                                forItemWithIdentifier: RenditionCollectionViewItem.reuseIdentifier)
        collectionView.register(RenditionTypeHeaderView.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: RenditionTypeHeaderView.identifier)
        addSnapshot(collectionToAdd: collection)
        
        splitViewParent?.handler = { [unowned self] item, didCollapse, _ in
            guard item.viewController.identifier == "RenditionInfo" else { return }
            collectionView.collectionViewLayout = makeLayout(
                layout: didCollapse ? .horizontal : .vertical
            )
            
            collectionView.identifier = didCollapse ? "HorizLayout" : "VerticalLayout"
        }
        
        let scrollView = NSScrollView()
        scrollView.verticalScroller = nil
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = false
        
        view = scrollView
        view.frame.size = CGSize(width: 724, height: 676)
        
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: nil) { [unowned self] _ in
            let vc = splitViewParent?.splitViewItems[0].viewController as? TypesListViewController
            guard let vc, let currentSection = collectionView.indexPathsForVisibleItems().first?.section else {
                return
            }
            
            vc.ignoreChanges = true
            vc.tableView.deselectRow(vc.tableView.selectedRow)
            vc.tableView.selectRowIndexes([currentSection], byExtendingSelection: true)
            vc.ignoreChanges = false
        }
    }
    
    @discardableResult
    func addSnapshot(collectionToAdd: RenditionCollection) -> NSDiffableDataSourceSnapshot<RenditionType, Rendition> {
        var snapshot = NSDiffableDataSourceSnapshot<RenditionType, Rendition>()
        for item in collectionToAdd {
            snapshot.appendSections([item.type])
            snapshot.appendItems(item.renditions, toSection: item.type)
        }
        
        dataSource.apply(snapshot)
        return snapshot
    }
    
    @discardableResult
    func refreshAssetCatalog() -> Bool {
        do {
            let (newCatalog, newCollection) = try AssetCatalogWrapper.shared.renditions(forCarArchive: fileURL)
            self.catalog = newCatalog
            self.collection = newCollection
            addSnapshot(collectionToAdd: collection)
            return true
        } catch {
            NSAlert(title: "Failed to refresh Asset Catalog", message: error.localizedDescription)
                .runModal()
            return false
        }
    }
    
}

extension RenditionListViewController: MenuProvider {
    func collectionView(_ collectionView: NSCollectionView, menuForItemAt indexPath: IndexPath) -> NSMenu? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let copyName = ClosureMenuItem(title: "Copy Name") {
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(item.name, forType: .string)
        }
        
        var items = [copyName]
        
        switch item.representation {
        case .image(let cgImage):
            let copyImage = ClosureMenuItem(title: "Copy Image") {
                NSPasteboard.general.declareTypes([.tiff], owner: nil)
                NSPasteboard.general.setData(NSImage(cgImage: cgImage, size: cgImage.size).tiffRepresentation, forType: .tiff)
            }
            items.append(copyImage)
        default:
            break
        }
        
        let deleteItem = ClosureMenuItem(title: "Delete") { [unowned self] in
            let alert = NSAlert(title: "Are you sure you want to delete \(item.name)?",
                                message: "This action cannot be undone")
            let deleteButton = alert.addButton(withTitle: "Delete")
            deleteButton.target = self
            deleteButton.action = #selector(deleteItem(sender:))
            
            if #available(macOS 11, *) {
                deleteButton.hasDestructiveAction = true
            }
            
            itemToDeleteIndexPath = indexPath
            alert.addButton(withTitle: "Cancel")
            alert.runModal()
        }
        
        items.append(deleteItem)
        return NSMenu(items: items)
    }
    
    @objc
    func deleteItem(sender: NSButton) {
        guard let itemToDeleteIndexPath,
                let item = dataSource.itemIdentifier(for: itemToDeleteIndexPath) else {
            return
        }
        
        do {
            try catalog.removeItem(item, fileURL: fileURL)
            NSApplication.shared.abortModal()
            refreshAssetCatalog()
        } catch {
            NSAlert(title: "Failed to remove \(item.name)", message: error.localizedDescription)
                .runModal()
            return
        }
    }
}

extension RenditionListViewController {
    @objc
    func infoButtonClicked(sender: NSButton) {
        guard let ass = CUICommonAssetStorage(path: fileURL.path, forWriting: false) else {
            NSAlert(
                title: "Failed to display details of Assets.car file",
                message: "Failed to init CUICommonAssetStorage for \(fileURL.path)"
            )
            .runModal()
            return
        }
        
        /*
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 200)
         */
        
        let detailsView = AssetCatalogDetailsView(assetStorage: ass) { [unowned self] in
            // Callback for 'Done' button
            guard let currentlyPresenting = presentedViewControllers?.first else { return }
            dismiss(currentlyPresenting)
        }
        
        presentAsSheet(NSHostingController(rootView: detailsView))
    }
}

extension RenditionListViewController {
    // MARK: - Layout
    enum LayoutMode {
        case vertical
        case horizontal
    }
    
    func makeLayout(layout: LayoutMode) -> NSCollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(115))
        
        let group: NSCollectionLayoutGroup
        switch layout {
        case .vertical:
            group = .vertical(layoutSize: groupSize, subitems: [item]/*, count: 3*/)
        case .horizontal:
            group = .horizontal(layoutSize: groupSize, subitem: item, count: 3)
        }
        
        let spacing = CGFloat(15)
        group.interItemSpacing = .fixed(spacing)
        
        let titleHeaderSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(50)
        )
        
        let titleSupplementary = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: titleHeaderSize,
            elementKind: NSCollectionView.elementKindSectionHeader,
            alignment: .topTrailing
        )
        
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 20,
                                                        leading: spacing,
                                                        bottom: 20,
                                                        trailing: spacing)
        section.boundarySupplementaryItems = [titleSupplementary]
        //section.orthogonalScrollingBehavior = .continuous
        return NSCollectionViewCompositionalLayout(section: section)
    }
}

extension RenditionListViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        return [indexPaths.first!]
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let firstIndexPath = indexPaths.first,
              let item = dataSource.itemIdentifier(for: firstIndexPath),
              let parent = splitViewParent else {
            return
        }
        
        let layer = collectionView.item(at: firstIndexPath)?.view.layer
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 3.5 // enlargen border width when selected
        
        // if we already have an existing info vc then remove it
        if parent.splitViewItems.count == 3 {
            parent.removeSplitViewItem(parent.splitViewItems[2])
        }
        
        let view = RenditionInformationView(rendition: item, catalog: catalog, fileURL: fileURL) { [unowned self] change in
            switch change {
            case .delete:
                refreshAssetCatalog()
            case .edit:
                if refreshAssetCatalog() {
                    self.collectionView(collectionView, didSelectItemsAt: indexPaths)
                }
            }
        }
        
        let renditionVC = NSHostingController(rootView: view)
        renditionVC.identifier = "RenditionInfo"
        let splitViewItem = NSSplitViewItem(contentListWithViewController: renditionVC)
        splitViewItem.minimumThickness = 400
        splitViewItem.canCollapse = true
        splitViewItem.maximumThickness = 600
        splitViewItem.automaticMaximumThickness = 600
        splitViewItem.preferredThicknessFraction = 2
        
        parent.addSplitViewItem(splitViewItem)
        
        if collectionView.identifier == "HorizLayout" {
            collectionView.collectionViewLayout = makeLayout(layout: .vertical)
            collectionView.identifier = "VerticalLayout"
            // scroll back here because switching between layouts may cause the item to not be visible
            // in the new layout
            collectionView.scrollToItems(at: indexPaths,
                                         scrollPosition: [.centeredVertically, .centeredHorizontally])
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            let layer = collectionView.item(at: indexPath)?.view.layer
            layer?.borderColor = NSColor.systemGray.cgColor
            layer?.borderWidth = 1.87 // standard
        }
    }
    
    override func performTextFinderAction(_ sender: Any?) {
        for item in view.window?.toolbar?.items ?? [] {
            if let search = item.view as? NSSearchField {
                search.becomeFirstResponder()
                break
            }
        }
    }
    
    /*
    func collectionView(_ collectionView: NSCollectionView,
                        canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return indexPaths.allSatisfy { [unowned self] indxPath in
            switch dataSource.itemIdentifier(for: indxPath)?.type {
            case .image, .icon:
                return true
            default:
                return false
            }
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        print(#function)
    }
     */
}

extension RenditionListViewController: NSSearchFieldDelegate {
    
    /// Set the types in the sidebar,
    /// if nil, then this will default to all the types
    func setSidebarTypes(_ types: [RenditionType]?) {
        if let sidebar = splitViewParent?.splitViewItems[0].viewController as? TypesListViewController {
            sidebar.types = types ?? sidebar.allTypes
            sidebar.tableView.reloadData()
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let searchText = (obj.object as? NSSearchField)?.stringValue else { return }
        
        if searchText.isEmpty {
            dataSource.apply(allItemsSnapshot)
            setSidebarTypes(nil)
            return
        }
        
        var newSidebarTypes: [RenditionType] = []
        let newCollection: RenditionCollection = collection.compactMap { type, renditions in
            // query by the renditions that have the search text in their name
            let newRends = renditions.filter { rend in
                return rend.name.localizedCaseInsensitiveContains(searchText)
            }
            
            // Don't include the section if no items match the query
            if newRends.isEmpty {
                return nil
            }
            
            // the section has renditions that match our description, add it to the sidebar
            newSidebarTypes.append(type)
            
            return (type, newRends)
        }
        
        addSnapshot(collectionToAdd: newCollection)
        
        setSidebarTypes(newSidebarTypes)
        
    }
}