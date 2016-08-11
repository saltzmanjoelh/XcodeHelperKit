Build your Swift code on Linux with Xcode
Archive your project and upload to S3 for automatic deployment with Xcode Server
Keep the Xcode references to Swift dependency sources updated so that you don't have to keep change them when your dependencies update.

Helps with the Linux side of cross-platform Swift. Building and testing your Swift code in Xcode on the macOS is one thing. But, you then have to fire up Docker and make sure that there aren't any language differences or library differences on the Linux side of things. It's kind of a pain.

You can use the XcodeHelper as a binary. Then, create a new External Build target in Xcode. Now, when you are building your project, you can see the LInux errors right in Xcode. You can also have XcodeHelper archive your project into a tar file and upload to S3. The goal is to let Xcode Server handle the continuous integration for both macOS and Linux (via Docker) so that we don't have to use a intermediary build server like Jenkins. 


Detailed instructions to come later 
