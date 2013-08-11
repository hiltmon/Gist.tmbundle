# Gist.tmbundle

A TextMate 2 bundle to create, get and update GitHub gists. 

A command-line version is available at [hiltmon/gist](https://github.com/hiltmon/gist).

## Usage

**Warning:** Before you can create, update or pick gists, you need to set up Authentication (see below)

In TextMate, hit `⇧⌃⌘J` to bring up the Gists menu (or pick it from the `cog` menu in the status bar):

* **Get Gist:** Brings up a dialog where you can paste the Gist ID or URL to retrieve. If any text is selected, it guesses the last number is the gist id. *Get Gist* downloads all the files in the gist to the current folder, saves them and opens them in TextMate 2. **Note:** If a file name already exists, *Get Gist* overwrites it.
* **Pick my Gists:** Displays up to 100 (API limit) of your own Gists to get. Select a gist to download all the files in that gist, save them and open them in TextMate. **Note:** If a file name already exists, *Pick my Gist* overwrites it.
* **Copy Gist URL:** Copies the current file's Gist URL to the clipboard if the file is a cached gist.
* **View Gist On Web:** Opens the current file's Gist URL in the default browser if the file is a cached gist.
* **Update Gist:** Updates the current file for the Gist on the web if the file is a cached gist.
* **Add File to Gist:** Brings up a list of your gists and enables you to add the current file to the gist you choose.
* **Create Public Gist:** Creates a new public gist containing the current file's contents. Leaves the URL of the new gist on the clipboard.
* **Create Private Gist:** Creates a new private to you only gist containing the current file's contents. Leaves the URL of the new gist on the clipboard.
* **Gist from Selection:** Creates a new *public* gist with the contents of the selection, leaving the URL of the new gist on the clipboard. **Note** that these gists are not cached as they have no file names.  It also assumes the language for the file extension the selection comes from (if the file is saved).

Some limitations to be aware of:

* Gists have no path information, so be careful to use unique file names for files in gists. This bundle will map a unique file name to a unique gist id. If the same file name exists elsewhere, this bundle will assume its the same file from another gist.
* Although you can download multi-file gists, the create and update processes only work with the current file. Use **Add File to Gist** to create multi-file gists after creating one with an original file.

## The Cache

This plugin caches the mapping between file names and gist id's in the file `~/.gists`. This cache is shared with my [cached gist command](https://github.com/hiltmon/gist) for command line use. The bundle uses this cache to enable updates to gists without the user having to remember gist id's (and because TextMate does not have any way to add custom attributes to open files).

## Installation

You can find this bundle in TextMate → Preferences → Bundles → Gist where it can be enabled.

To install via Git:

    mkdir -p ~/Library/Application\ Support/Avian/Bundles
    cd ~/Library/Application\ Support/Avian/Bundles
    git clone git://github.com/hiltmon/Gist.tmbundle

## Authentication

There are two ways to set GitHub user and password info:

Using the environment variables vars GITHUB_USER and GITHUB_PASSWORD in either the shell or TextMate variables:

	$ export GITHUB_USER="your-github-username"  
	$ export GITHUB_PASSWORD="your-github-password"  


Or by having your git config set up with your GitHub username and password **(Recommended)**.

	git config --global github.user "your-github-username"  
	git config --global github.password "your-github-password"  

## Contributing

This is but the first version of this bundle. If you have any ideas or wish to contribute, go ahead.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

# License
(The MIT License)

Copyright (c) 2013 Hilton Lipschitz, [http://www.hiltmon.com](http://www.hiltmon.com), [hiltmon@gmail.com](mailto:hiltmon@gmail.com).  
Includes files from JSON by Florian Frank<flori at ping dot de>.  

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the 'Software'), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

