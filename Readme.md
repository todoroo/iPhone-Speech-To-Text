Speech-to-Text library used by Astrid for iPhone!

This library leverages the Google Voice API and the Speex audio codec to achieve speech-to-text
on iOS devices where Siri is not available. The library includes version 1.2-rc1 of the
Speex codec and three supporting classes to make speech-to-text on iOS as simple as possible.
There are a few steps required to configure the project in Xcode:

1) Clone the project

2) Add the SpeechToText Xcode project to your project

3) In your project's settings, update the target's build phases by adding SpeechToText
   to the "Target Dependencies" section and libSpeechToText.a under the "Link Binary with Libraries"
   section.

4) Under the target's Build Settings tab, add the iPhone-Speech-to-Text directory (i.e. the path
   on your hard drive to wherever it exists) to the "Header Search Paths" field, and click the box
   marked "Recursive"

5) Import "SpeechToTextModule.h" wherever you want to use it!

The SpeechToTextModule class is the core of the library, but is very simple. An instance of this
class can start and stop audio recording, and will pass an NSData * object back to its delegate
when it receives a response from the Google Voice API. This data should be interpreted as JSON and
can be decoded by your favorite JSON parsing library. The resulting JSON object
should contain an array under the key "hypotheses", and each entry in this array will be a possible
interpretation of the audio with the key "utterance" for the text and the key "confidence" for
the confidence.

Optional delegate methods for SpeechToTextModuleDelegate allow you to display a rolling sine wave
view that indicates volume amplitude as recording takes place (showSineWaveView and dismissSineWaveView)
or display an optional loading view while the module communicates with the voice API.


Contributors workflow
---------------

If you want to help make this library better, read this!

**Setup:**

`git clone git@github.com:your-github-id/iPhone-Speech-to-Text.git` (your-github-id should obviously be replaced)

`git remote add upstream git@github.com:todoroo/iPhone-Speech-to-Text.git`

**Working on new features/fixes:**

`git checkout -b my-new-features upstream/master`  

work, work, work! 
  
`git commit` (a separate commit for each bug fix, feature change, style or copy edit please!)
  
`git fetch upstream`

`git rebase -i upstream/master` (i like to rebase -i to verify what I'm committing and squish small commits)
  
`git push origin HEAD`
  
then go to github and submit a pull request!  

For further information, read [Tim's Collaborator Guide](http://www.betaful.com/2011/04/git-for-ongoing-collaboration/).
