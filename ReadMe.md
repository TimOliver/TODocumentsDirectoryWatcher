# TODocumentsDirectoryWatcher

<img src="https://raw.github.com/TimOliver/TODocumentsDirectoryWatcher/master/Screenshots/TODocumentsDirectoryWatcher_iPhone5s.jpg" alt="TODocumentsDirectoryWatcher on iPhone 5s" width="392" align="center" />

TODocumentsDirectoryWatcher is an open-source singleton module, designed to observe your iOS app's Documents directory, and post NSNotifiction messages whenever it detects that a file/folder is added, renamed, or deleted within it.

The goal of this module is to be able to explicilty detect when a user has modified the contents of the Documents folder from outside the app, such as the documents sharing window in iTunes on Mac/PC, even if the app was closed in the interim.

This originally started off as an implementation in my iOS app, iComic (http://icomics.co) in order to detect when a user had dragged a comic file from their Desktop into the app itself via iTunes, so that the app may start importing/processing the file once it's finished copying. I've made it open-source in the hopes that others may find it useful, and might know of ways to help improve it.

## Features
* Can detect when a batch of new files is added to the Documents directory, and will notify the system after all of the files have finished copying.
* Using the Unix file-system structure, it can detect when files in the Documents directory have been renamed.
* Can detect when a file has been deleted from the Documents directory.
* Using cached snapshots of the Documents directory, these file operations can be tracked even if they've occurred while the app was closed.
* Performs all of its work in serial dispatch queues for maximum responsiveness.

## Technical Requirements
iOS 4.0 or above.

## License

TODocumentsDirectoryWatcher is licensed under the MIT License. Attribution is not required, but it is appreciated!
- - -
Copyright 2014 Timothy Oliver. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.