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


import BXSwiftUtils
import SwiftUI
import QuickLook

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(AppKit)
import AppKit
#endif


//----------------------------------------------------------------------------------------------------------------------


open class FolderContainer : Container
{
	/// Will be set to true if a folder was deleted in the Finder
	
	@Published public private(set) var isMissing = false
	
	/// The security scoped folder URL this Container holds access to, if access was granted. Released
	/// in deinit. Non-nil only when startAccessingSecurityScopedResource() succeeded, since a stop
	/// call must not be made for a start that failed.
	
	private var scopedFolderURL:URL? = nil

	/// Creates a new Container for the folder at the specified URL
	
	public required init(url:URL, name:String? = nil, filter:FolderFilter, removeHandler:((Container)->Void)? = nil, in library:Library?)
	{
		// Get the display name
		
		let displayName = name ?? FileManager.default.displayName(atPath:url.path)
		
		// Hold access to the folder for as long as this Container exists. A security scoped URL has to
		// be accessed between a start and a stop call, and a folder Container needs that access for its
		// whole lifetime - to enumerate its contents, load thumbnails, and hand out file URLs - so the
		// scope is acquired once here and relinquished in deinit rather than being re-acquired by
		// everything that happens to need it.
		//
		// The scope must be open before the bookmark is made. A URL resolved from a saved bookmark
		// carries no access until it is started, and making a security scoped bookmark without access
		// fails. That used to leave the Container with empty data: it could not load, and the next save
		// replaced the user's working bookmark with the empty one, losing the folder.
		
		let isAccessingScope = url.startAccessingSecurityScopedResource()
		let bookmark = (try? url.bookmarkData()) ?? Data()
		
		// Init the Container
		
		super.init(
			identifier: FolderSource.identifier(for:url),
			name: displayName,
			data: bookmark,
			filter: filter,
			loadHandler: Self.loadContents,
			removeHandler: removeHandler,
			in: library)
		
		if isAccessingScope
		{
			self.scopedFolderURL = url
		}
		
		// Observe changes of folder contents
		
		self.setupContentObserver(for:url, customName:name)

		// On macOS also add drop detection
		
		#if os(macOS)
		self.fileDropDestination = FolderDropDestination(folderURL:url)
		#endif
	}


	/// Creates a FolderObserver for the specified folder
	
	private func setupContentObserver(for url:URL, customName:String?)
	{
		// Create a FolderObserver that tracks changes to this directory
		
		let observer = FolderObserver(url:url)
		self.observer = observer
		
		// Reload the Container whenever the folder contents have changed
		
		observer.folderContentsDidChange =
		{
			[weak self] in
			self?.reload()
		}

		// Rename the Container when the folder was renamed in the Finder. Please note that we also have
		// to create a new FolderObserver for the folder because the old one doesn't work anymore. Also
		// reload the Container, so that the URLs of all Objects inside are updated!
		
		observer.folderWasRenamed =
		{
			[weak self] in
			guard let self = self else { return }
			guard let url = self.folderURL else { return }

			self.isMissing = false
			self.name = customName ?? FileManager.default.displayName(atPath:url.path)		// Update Container name
			self.setupContentObserver(for:url, customName:customName)						// Old observer doesn't work anymore, so create a new one
			self.reload()																	// Update Objects inside the container (new URL paths!)
			
			FolderSource.log.debug {"\(Self.self).\(#function) folder at \(url.path) was renamed"}
		}
		
		// Mark this Container as missing if the folder was deleted in the Finder
		
		observer.folderWasDeleted =
		{
			[weak self] in
			self?.isMissing = true
			FolderSource.log.debug {"\(Self.self).\(#function) folder at \(url.path) was deleted"}
		}
		
		observer.resume()
	}
	
	
	/// This helper report any external changes to the folder
	
	private var observer:FolderObserver? = nil


//----------------------------------------------------------------------------------------------------------------------


	/// Returns the URL to the folder
	
	public var folderURL:URL?
	{
		// Return the URL whose access this Container already holds. This used to resolve the bookmark
		// and start a new security scope on every single access, none of which was ever stopped.
		
		if let scopedFolderURL = self.scopedFolderURL { return scopedFolderURL }
		
		guard let bookmark = self.data as? Data else { return nil }
		return URL(with:bookmark)
	}
	
	
	deinit
	{
		self.scopedFolderURL?.stopAccessingSecurityScopedResource()
	}
	
	/// Returns the list of allowed sort Kinds for this Container
		
	override open var allowedSortTypes:[Object.Filter.SortType]
	{
		[.captureDate,.alphabetical,.rating,.useCount]
	}


	// This container can be expanded if it has subfolders. Since it is fairly expensive to scan a directory just to
	// find out whether it has any subfolders, we will perform the scanning on a background task. In the meantime we
	// will return a default value of false (meaning that no disclosure triangle is displayed in the user interface.
	// Once the result is available, it will be assigned to the published helper property 'hasSubfolders' which will
	// trigger the UI to be updated automatically.
	
	override open var canExpand: Bool
	{
		if self.isLoaded { return !self.containers.isEmpty }
		
		if !didScanSubfolders
		{
			self.didScanSubfolders = true
			
			Task
			{
				guard let folderURL = self.folderURL else { return }
				let result = folderURL.hasSubfolders
				await MainActor.run { self.hasSubfolders = result }
			}
		}

		return self.hasSubfolders
	}
	
	private var didScanSubfolders = false
	
	@MainActor @Published public private(set) var hasSubfolders = false

	
//----------------------------------------------------------------------------------------------------------------------


	// MARK: - Loading
	
	/// Loads the (shallow) contents of this folder
	
	class func loadContents(for identifier:String, data:Any, filter:Object.Filter, in library:Library?) async throws -> Loader.Contents
	{
		FolderSource.log.debug {"\(Self.self).\(#function) \(identifier)"}

		var containers:[Container] = []
		var objects:[Object] = []
		
		// Convert identifier to URL and perform some sanity checks
		
		guard let bookmark = data as? Data else { throw Error.notFound }
		guard let folderURL = URL(with:bookmark) else { throw Error.notFound }
		
		// This resolves a fresh URL, so it needs its own scope, and must relinquish it before returning.
		// The Container itself holds access for its lifetime, so releasing this one does not revoke
		// access to the folder.
		
		guard folderURL.startAccessingSecurityScopedResource() else { throw Error.accessDenied }
		defer { folderURL.stopAccessingSecurityScopedResource() }
		guard folderURL.exists else { throw Error.notFound }
		guard folderURL.isDirectory else { throw Error.notFound }
		guard folderURL.isReadable else { throw Error.accessDenied }
		guard let filter = filter as? FolderFilter else { throw Error.loadContentsFailed }
		
		// Get the folder contents
		
		let filenames = try self.filenames(in:folderURL)
		
		// Convert to file URLs
		
		guard !Task.isCancelled else { throw Error.loadContentsCancelled }

		let urls = filenames.compactMap
		{
			(filename:String) -> URL? in
			let url = folderURL.appendingPathComponent(filename)
			guard url.isFileURL else { return nil }
			guard url.isReadable else { return nil }
			guard !url.isHidden else { return nil }
			return url
		}
		
		// Each subdirectory becomes a Container
		
		for url in urls where url.isDirectory && !url.isPackage
		{
			guard !Task.isCancelled else { throw Error.loadContentsCancelled }
			
			if let container = try? Self.createContainer(for:url, filter:filter, in:library)
			{
				containers.append(container)
			}
		}
		
		// The files shown are this folder's own, or with Config.Folders.includesSubfolderContents also those of all
		// its subfolders
		
		let fileURLs = Config.Folders.includesSubfolderContents ?
			try self.fileURLsIncludingSubfolders(of:folderURL) :
			urls.filter { !($0.isDirectory && !$0.isPackage) }
		
		for url in fileURLs
		{
			guard !Task.isCancelled else { throw Error.loadContentsCancelled }
			
			// If a file meets the filter criteria create an Object
			
			if let url = Self.filter(url, with:filter)
			{
				if let object = try? Self.createObject(for:url, filter:filter, in:library)
				{
					if filter.rating == 0 || StatisticsController.shared.rating(for:object) >= filter.rating
					{
						objects.append(object)

						// For sorting by capture date we need to make sure a date is available
						
						if filter.sortType == .captureDate
						{
							let metadata = try? await object.loader.metadata
							object.captureDate =
								(metadata?[.captureDateKey] as? Date) ??
								url.creationDate
						}
					}
				}
			}
		}
		
		// Sort according to specified sort order
		
		guard !Task.isCancelled else { throw Error.loadContentsCancelled }

		filter.sort(&objects)
		
		// Return contents
		
		return (containers,objects)
	}
	
	
	/// Returns the names of all files inside this folder
	
	/// Returns the files in a folder and all of its subfolders, in the order the Finder would list them folder by
	/// folder. Hidden files and the contents of packages are left out, as they are for a single folder, and symbolic
	/// links to folders are not followed, so a link back up the hierarchy cannot make the walk endless.
	
	class func fileURLsIncludingSubfolders(of folderURL:URL) throws -> [URL]
	{
		let keys:[URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isReadableKey]
		
		guard let enumerator = FileManager.default.enumerator(at:folderURL, includingPropertiesForKeys:keys, options:[.skipsHiddenFiles, .skipsPackageDescendants]) else
		{
			return []
		}
		
		var fileURLs:[URL] = []
		
		for case let url as URL in enumerator
		{
			guard !Task.isCancelled else { throw Error.loadContentsCancelled }
			
			let values = try? url.resourceValues(forKeys:Set(keys))
			let isFolder = values?.isDirectory == true && values?.isPackage != true
			guard !isFolder, values?.isReadable != false else { continue }
			
			fileURLs.append(url)
		}
		
		return fileURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
	}
	
	class func filenames(in folderURL:URL) throws -> [String]
	{
		if #available(macOS 12, iOS 15, *)
		{
			return try FileManager.default
				.contentsOfDirectory(atPath:folderURL.path)
				.sorted(using:.localizedStandard)
		}
		else
		{
			return try FileManager.default
				.contentsOfDirectory(atPath:folderURL.path)
				.sorted()
		}
	}
	
	
	/// Check if the specified URL meets the filter criteria. Returns the URL itself if yes, or nil if not.
	
	open class func filter(_ url:URL, with filter:FolderFilter) -> URL?
	{
		let searchString = filter.searchString.lowercased()
		guard !searchString.isEmpty else { return url }
		
		let filename = url.lastPathComponent.lowercased()
		return filename.contains(searchString) ? url : nil
	}
	
	
	/// Creates a Container (of same type) for the folder at the specified URL.
	///
	/// Subclasses can override this function to filter out some directories.
	
	open class func createContainer(for url:URL, filter:FolderFilter, in library:Library?) throws -> Container?
	{
		guard url.exists else { throw Container.Error.notFound }
		guard url.isDirectory else { throw Container.Error.notFound }
		guard url.isReadable else { throw Container.Error.accessDenied }
		
		return Self.init(url:url, filter:filter, in:library)
	}


	/// Creates a Object for the file at the specified URL.
	///
	/// Subclasses can override this function to filter out some files.
	
	open class func createObject(for url:URL, filter:FolderFilter, in library:Library?) throws -> Object?
	{
		// Depending on file UTI create different Object subclass instances
		
		if url.isImageFile
		{
			return ImageFile(url:url, in:library)
		}
		else if url.isVideoFile
		{
			return VideoFile(url:url, in:library)
		}
		else if url.isAudioFile
		{
			return AudioFile(url:url, in:library)
		}
		else
		{
			return FolderObject(url:url, in:library)
		}
	}
	
	
	/// If the container caches any expensive data, calling this function will discard any cached data
	
	override func invalidateCache()
	{
		super.invalidateCache()
		self.didScanSubfolders = false
		self.hasSubfolders = false
	}
	
	
//----------------------------------------------------------------------------------------------------------------------


	// MARK: - Actions
	
	/// Reveals the folder in the Finder
	
	open func revealInFinder()
	{
		guard let url = self.folderURL else { return }
		guard url.exists else { return }
		
		#if os(macOS)
		
		NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath:url.deletingLastPathComponent().path)
	
		#else
		
		#warning("TODO: implement for iOS")
		
		#endif
	}

}


//----------------------------------------------------------------------------------------------------------------------
