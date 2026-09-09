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


//----------------------------------------------------------------------------------------------------------------------


/// Lets the host application supply the pasteboard content for a dragged Object.
///
/// BXMediaBrowser knows how to deliver an Object's file, via the NSFilePromiseProvider returned by
/// Object.filePromiseProvider, but it cannot know what else the host needs on the pasteboard. An application
/// that attaches its own representation to a dragged item - a document model object, styled markup, or any
/// other payload that depends on application state at the time the drag begins - can implement this protocol
/// and return a writer of its own.
///
/// Assign an implementation to Library.dragDelegate. Returning nil from the delegate method accepts
/// BXMediaBrowser's default file promise, so adopting this protocol is never all-or-nothing: a host can
/// supply its own writer for some Objects and defer to the default for the rest.

public protocol ObjectDragDelegate : AnyObject
{
	/// Returns the pasteboard writer for a dragged Object, or nil to use BXMediaBrowser's default
	/// NSFilePromiseProvider.
	///
	/// Called when the drag begins, so the returned writer may capture host state that is current at that
	/// moment and would no longer be available at drop time.
	
	@MainActor func pasteboardWriter(for object:Object) -> NSPasteboardWriting?
}


#endif
