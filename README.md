
<p align="center"><img src="/test/logo.png" width="622"></p>

A CocoaPods plugin to integrate pods in form of prebuilt frameworks, not source code, by adding **just one flag** in podfile. Speed up compiling dramatically.

Good news: Introduction on cocoapods offical site: [Pre-compiling dependencies](http://guides.cocoapods.org/plugins/pre-compiling-dependencies.html) ( NOTE: This plugin is a community work, not official.)


## Why

You may wonder why CocoaPods doesn't have a function to integrate libs in form of binaries, if there are dozens or hundreds of pods in your podfile and compile them for a great many times meaninglessly. Too many source code of libs slow down your compile and the response of IDE (e.g. code completion), and then reduce work efficiency, leaving us time to think about the meaning of life.

This plugin implements this simple wish. Replace the source code in pod target with prebuilt frameworks.

Why don't use Carthage? While Carthage also integrates libs in form of frameworks, there several reasons to use CocoaPods with this plugin:

- Pod is a good simple form to organize files, manage dependencies. (private or local pods)
- Fast switch between source code and binary, or partial source code, partial binaries.
- Some libs don't support Carthage.

## How it works

It will compile the source code of pods during the pod install process, and make CocoaPods use them. Which pod should be compiled is controlled by the flag in Podfile.

#### Under the hood

( You could leave this paragraph for further reading, and try it now. )

The plugin will do a separated completed 'Pod install' in the standard pre-install hook. But we filter the pods by the flag in Podfile here. Then build frameworks with this generated project by using xcodebuild. Store the frameworks in `Pods/_Prebuild` and save the manifest.lock file for the next pod install.

Then in the flowing normal install process, we hook the integration functions to modify pod specification to using our frameworks.

## Installation

    $ gem install cocoapods-binary

## Usage

``` ruby
plugin 'cocoapods-binary'

use_frameworks!
# all_binary!

target "HP" do
    pod "ExpectoPatronum", :binary => true
end
```

- Add `plugin 'cocoapods-binary'` in the head of Podfile 
- Add `:binary => true` as a option of one specific pod, or add `all_binary!` before all targets, which makes all pods binaries.
- pod install, and that's all

**Note**: cocoapods-binary require `use_frameworks!`. If your worry about the boot time and other problems introduced by dynamic framework, static framework is a good choice. Another [plugin](https://github.com/leavez/cocoapods-static-swift-framework) made by me to make all pods static frameworks is recommended.

#### Options

If you want to disable binary for a specific pod when using `all_binary!`, place a `:binary => false` to it.

If your `Pods` folder is excluded from git, you may add `keep_source_code_for_prebuilt_frameworks!` in the head of Podfile to speed up pod install, as it won't download all the sources every time prebuilt pods have changes.

If bitcode is needed, add a `enable_bitcode_for_prebuilt_frameworks!` before all targets in Podfile

## Questions

1. Why is the initial precompilation a lengthy task?

The gem builds each pod for all architectures (simulator and devices seperately) and with >100 pods unfortauntely this can take a while. Additionally xcodebuild cli is run serially and synchronously, rather than in parralel if you use Xcode GUI build system. 

2. How do I reduce the build time when I clone a project?

Our daily develop CI job updates a [Triller-Pods](https://github.com/TrillerCo/Triller-Pods) repo that you can fetch using `git submodule update --init --recursive` 

3. How can I rebuild a pod?

A pod is built if your `Podfile.lock` in the root project directory is out of sync with the `Manifest.lock` file in `Pods` -> `_Prebuild` . You can manually remove a dependancy in the `Manifest.lock` file or reduce the version used and it should force an update.

4. Can I use a mix of precompiled and regular pods?

Unfortunately not.

5. Can I disable precompiled pods?

Sure, you can comment out the following two lines in your Podfile:

```
all_binary!
keep_source_code_for_prebuilt_frameworks!
```
