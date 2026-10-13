//----------------------------------------------------------------------------------------------------------------------
//
//  Copyright ©2022 Peter Baumgartner. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//----------------------------------------------------------------------------------------------------------------------


#if os(macOS)

import AppKit
import BXSwiftUtils
import QuickLookUI


//----------------------------------------------------------------------------------------------------------------------


public class BXObjectCollectionView : QuicklookCollectionView
{
	public static let getInfoNotification = Notification.Name("BXObjectCollectionView.getInfo")
	public static let selectAllNotification = Notification.Name("BXObjectCollectionView.selectAll")
	public static let deselectAllNotification = Notification.Name("BXObjectCollectionView.deselectAll")
	public static let selectObjectsNotification = Notification.Name("BXObjectCollectionView.selectObjects")
	
	internal var observers:[Any] = []
	
	/// Supplies the host's file drop delegate, if it has one, for the Container currently shown

	var fileDropDelegateProvider:(()->ObjectBrowserFileDropDelegate?)? = nil

	/// The identifiers of Objects to select once they appear, as asked for by selectObjects(withIdentifiers:)

	private var pendingSelectionIdentifiers:[String]? = nil

	
//----------------------------------------------------------------------------------------------------------------------


	override public init(frame:NSRect)
	{
		super.init(frame:frame)
		
		self.observers += NotificationCenter.default.publisher(for:Self.getInfoNotification, object:nil).sink
		{
			[weak self] _ in self?.getInfo()
		}
		
		self.observers += NotificationCenter.default.publisher(for:Self.selectAllNotification, object:nil).sink
		{
			[weak self] _ in self?.selectAll(nil)
		}
		
		self.observers += NotificationCenter.default.publisher(for:Self.deselectAllNotification, object:nil).sink
		{
			[weak self] _ in self?.deselectAll(nil)
		}

		self.observers += NotificationCenter.default.publisher(for:Self.selectObjectsNotification, object:nil).sink
		{
			[weak self] notification in
			guard let identifiers = notification.object as? [String] else { return }
			self?.selectObjects(withIdentifiers:identifiers)
		}
	}
	
	required init?(coder:NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}
	
	
//----------------------------------------------------------------------------------------------------------------------


	// Pressing Cmd-I shows the Get Info popover
	
	override public func keyDown(with event:NSEvent)
	{
        func key(for event:NSEvent) -> Int
        {
            guard let str = event.charactersIgnoringModifiers?.utf16  else { return 0 }
            let i = str.startIndex
            guard i < str.endIndex else { return 0 }
            return Int(str[i])
        }

		let str = event.charactersIgnoringModifiers
		let key = key(for:event)

		// Delete and Forward Delete send the standard Delete action, which the host can implement to remove the
		// selected Objects, as Edit > Delete does. Without a taker, the key does what it always did.

		let deletionModifiers:NSEvent.ModifierFlags = [.command, .option, .control]
		if (key == NSDeleteCharacter || key == NSDeleteFunctionKey) && event.modifierFlags.isDisjoint(with:deletionModifiers)
		{
			if NSApp.sendAction(#selector(NSText.delete(_:)), to:nil, from:self) { return }
		}

        let indexes = self.selectionIndexPaths
        let n = indexes.count
        let objectCount = self.numberOfItems(inSection:0)
        
        // Custom behavior is only available for single selection
        
        if n == 1
        {
            let i = indexes.first?.item ?? 0

            // Cmd-I open info popover
            
            if event.modifierFlags.contains(.command) && str == "i"
            {
                self.getInfo()
            }
            
            // Left arrow key moves selection to prev object
            
            else if key == NSLeftArrowFunctionKey
			{
                if i > 0
                {
                    let indexPath = IndexPath(item:i-1, section:0)
                    self.selectionIndexPaths = Set([indexPath])
                    self.scrollToItems(at:[indexPath], scrollPosition:.nearestHorizontalEdge)
                    self.updatePreviewPanel()
                    self.delegate?.collectionView?(self, didSelectItemsAt:[indexPath])
                }
			}
            
            // Right arrow key moves selection to succ object
            
			else if key == NSRightArrowFunctionKey
			{
                if i < objectCount-1
                {
                    let indexPath = IndexPath(item:i+1, section:0)
                    self.selectionIndexPaths = Set([indexPath])
                    self.scrollToItems(at:[indexPath], scrollPosition:.nearestHorizontalEdge)
                    self.updatePreviewPanel()
                    self.delegate?.collectionView?(self, didSelectItemsAt:[indexPath])
                }
			}
            else
            {
                super.keyDown(with:event)
            }
        }
        
        // Multiple selection - let superclass handle that
        
        else
        {
            super.keyDown(with:event)
        }
	}


//----------------------------------------------------------------------------------------------------------------------


	/// Display the metadata Info popover for the selected Object
	
	public func getInfo()
	{
		guard let window = self.window else { return }
		guard window.isKeyWindow else { return }
		
		let indexPaths = self.selectionIndexPaths

		if indexPaths.count == 1, let indexPath = indexPaths.first, let item = self.item(at:indexPath) as? ObjectCell
		{
			item.getInfo()
		}
	}
	
	
	/// Returns the list of selected ObjectCells
	
	open var selectedCells:[ObjectCell]
	{
		self.selectionIndexPaths.compactMap
		{
			self.item(at:$0) as? ObjectCell
		}
	}


	/// Checks if any thumbnails of currently visible objects are missing, and reloads them if necessary.
	///
	/// This provides a self-healing effect for a situation that sometimes occurs, but the cause isn't understood yet.
	
	@objc public func reloadMissingThumbnails()
	{
		let visibleItems = self.visibleItems()
		
		for item in visibleItems
		{
			guard let cell = item as? ObjectCell else { continue }
			guard let object = cell.object else { continue }
			
			if object.thumbnailImage == nil
			{
				object.load()
			}
		}
	}
	
	
//----------------------------------------------------------------------------------------------------------------------


	/// Selects all object (in all browsers)

	public static func selectAll()
	{
		NotificationCenter.default.post(name:Self.selectAllNotification, object:nil)
	}

	/// Deselects all object (in all browsers)

	public static func deselectAll()
	{
		NotificationCenter.default.post(name:Self.deselectAllNotification, object:nil)
	}

	/// Selects the Objects with the specified identifiers (in all browsers), as if the user had clicked them.
	///
	/// An Object that is not shown yet, for example because its Container is still loading or was only just
	/// selected, is selected as soon as it appears. A click in the browser cancels a request still waiting.

	public static func selectObjects(withIdentifiers identifiers:[String])
	{
		NotificationCenter.default.post(name:Self.selectObjectsNotification, object:identifiers)
	}

	private func selectObjects(withIdentifiers identifiers:[String])
	{
		self.pendingSelectionIdentifiers = identifiers
		self.applyPendingSelection()
	}

	/// Selects any Objects still waiting to be selected, if they are now shown. Called whenever the shown
	/// Objects change.

	func applyPendingSelection()
	{
		guard let identifiers = self.pendingSelectionIdentifiers else { return }
		guard let dataSource = self.dataSource as? NSCollectionViewDiffableDataSource<Int,Object> else { return }

		let wanted = Set(identifiers)
		let indexPaths = Set(dataSource.snapshot().itemIdentifiers
			.filter { wanted.contains($0.identifier) }
			.compactMap { dataSource.indexPath(for:$0) })

		guard let first = indexPaths.sorted().first else { return }
		self.pendingSelectionIdentifiers = nil

		self.selectionIndexPaths = indexPaths
		self.scrollToItems(at:[first], scrollPosition:.nearestHorizontalEdge)

		// Setting the selection does not reach the delegate, which is what announces a selection to everyone
		// else, so tell it as a click would

		self.delegate?.collectionView?(self, didSelectItemsAt:indexPaths)
	}

	// MARK: - Filling the visible area

	// The collection view is otherwise only as tall as its rows, so with only a row or two, the space below them belongs
	// to the clip view, and a drop or a click there does not reach the browser. Keeping it at least as tall as the
	// visible area makes the whole of it the browser's.

	private var clipViewObserver:Any? = nil

	override public func setFrameSize(_ newSize:NSSize)
	{
		var size = newSize
		if let clipView = self.enclosingScrollView?.contentView
		{
			size.height = max(size.height, clipView.bounds.height)
		}
		super.setFrameSize(size)
	}

	override public func viewDidMoveToSuperview()
	{
		super.viewDidMoveToSuperview()

		self.clipViewObserver = nil
		guard let clipView = self.enclosingScrollView?.contentView else { return }

		clipView.postsFrameChangedNotifications = true
		self.clipViewObserver = NotificationCenter.default.publisher(for:NSView.frameDidChangeNotification, object:clipView).sink
		{
			[weak self] _ in
			guard let self = self else { return }
			let contentHeight = self.collectionViewLayout?.collectionViewContentSize.height ?? self.frame.height
			self.setFrameSize(NSSize(width:self.frame.width, height:contentHeight))
		}
		self.setFrameSize(self.frame.size)
	}

	// MARK: - Drops taken by the host

	// A host with a file drop delegate takes drops on the whole browser, so they are handled here rather than by
	// NSCollectionView's own drop handling, which offers a drop to its delegate only where the layout reports a drop
	// target, and the compositional layout reports none. Without a delegate, drops go to NSCollectionView as before,
	// and from there to the Container's fileDropDestination.

	private var fileDropDelegate:ObjectBrowserFileDropDelegate?
	{
		self.fileDropDelegateProvider?()
	}

	override public func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation
	{
		guard let fileDropDelegate = self.fileDropDelegate else { return super.draggingEntered(sender) }
		return fileDropDelegate.objectBrowser(canAcceptDrop:sender) ? .copy : []
	}

	override public func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation
	{
		guard let fileDropDelegate = self.fileDropDelegate else { return super.draggingUpdated(sender) }
		return fileDropDelegate.objectBrowser(canAcceptDrop:sender) ? .copy : []
	}

	override public func draggingExited(_ sender:NSDraggingInfo?)
	{
		guard self.fileDropDelegate == nil else { return }
		super.draggingExited(sender)
	}

	override public func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool
	{
		guard self.fileDropDelegate == nil else { return true }
		return super.prepareForDragOperation(sender)
	}

	override public func performDragOperation(_ sender:NSDraggingInfo) -> Bool
	{
		guard let fileDropDelegate = self.fileDropDelegate else { return super.performDragOperation(sender) }
		return fileDropDelegate.objectBrowser(acceptDrop:sender)
	}

	override public func concludeDragOperation(_ sender:NSDraggingInfo?)
	{
		guard self.fileDropDelegate == nil else { return }
		super.concludeDragOperation(sender)
	}

	// A click supersedes a selection still waiting for its Objects to appear

	override public func mouseDown(with event:NSEvent)
	{
		self.pendingSelectionIdentifiers = nil
		super.mouseDown(with:event)
	}

}


//----------------------------------------------------------------------------------------------------------------------


#endif
