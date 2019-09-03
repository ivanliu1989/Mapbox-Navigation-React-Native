import Foundation
import CoreLocation
import AVFoundation
import MapboxSpeech
import MapboxCoreNavigation
import MapboxDirections

/**
 The Mapbox voice controller plays spoken instructions using the [MapboxSpeech](https://github.com/mapbox/mapbox-speech-swift/) framework.
 
 You initialize a voice controller using a `NavigationService` instance. The voice controller observes when the navigation service hints that the user has passed a _spoken instruction point_ and responds by converting the contents of a `SpokenInstruction` object into audio and playing the audio.
 
 The MapboxSpeech framework requires a network connection to connect to the Mapbox Voice API, but it produces superior speech output in several languages including English. If the voice controller is unable to connect to the Voice API, it falls back to the Speech Synthesis framework as implemented by the superclass, `RouteVoiceController`. To mitigate network latency over a cell connection, `MapboxVoiceController` prefetches and caches synthesized audio.
 
 If you need to supply a third-party speech synthesizer that requires a network connection, define a subclass of `MapboxVoiceController` that overrides the `speak(_:)` method. If the third-party speech synthesizer does not require a network connection, you can instead subclass `RouteVoiceController`.
 
 The Mapbox Voice API is optimized for spoken instructions provided by the Mapbox Directions API via the MapboxDirections.swift framework. If you need text-to-speech functionality outside the context of a navigation service, use the Speech Synthesis framework’s `AVSpeechSynthesizer` class directly.
 */
@objc(MBMapboxVoiceController)
open class MapboxVoiceController: RouteVoiceController, AVAudioPlayerDelegate {
    
    /**
     Number of seconds a request can wait before it is canceled and the default speech synthesizer speaks the instruction.
     */
    @objc public var timeoutIntervalForRequest: TimeInterval = 5
    
    /**
     Number of steps ahead of the current step to cache spoken instructions.
     */
    @objc public var stepsAheadToCache: Int = 3
    
    /**
     An `AVAudioPlayer` through which spoken instructions are played.
     */
    @objc public var audioPlayer: AVAudioPlayer?
    
    var audioTask: URLSessionDataTask?
    var cache: BimodalDataCache
    let audioPlayerType: AVAudioPlayer.Type
    
    var speech: SpeechSynthesizer
    var locale: Locale?
    
    let localizedErrorMessage = NSLocalizedString("FAILED_INSTRUCTION", bundle: .mapboxNavigation, value: "Unable to read instruction aloud.", comment: "Error message when the SDK is unable to read a spoken instruction.")

    @objc public init(navigationService: NavigationService, speechClient: SpeechSynthesizer = SpeechSynthesizer(accessToken: nil), dataCache: BimodalDataCache = DataCache(), audioPlayerType: AVAudioPlayer.Type? = nil) {
        speech = speechClient
        cache = dataCache
        self.audioPlayerType = audioPlayerType ?? AVAudioPlayer.self
        super.init(navigationService: navigationService)
        
        audioPlayer?.delegate = self
        
        volumeToken = NavigationSettings.shared.observe(\.voiceVolume) { [weak self] (settings, change) in
            self?.audioPlayer?.volume = settings.voiceVolume
        }
        
        muteToken = NavigationSettings.shared.observe(\.voiceMuted) { [weak self] (settings, change) in
            if settings.voiceMuted {
                self?.audioPlayer?.stop()
             
                guard let strongSelf = self else { return }
                do {
                    try strongSelf.unDuckAudio()
                } catch {
                    strongSelf.voiceControllerDelegate?.voiceController?(strongSelf, spokenInstructionsDidFailWith: error)
                }
            }
        }
    }
    
    deinit {
        audioPlayer?.stop()
        do {
            try unDuckAudio()
        } catch {
            voiceControllerDelegate?.voiceController?(self, spokenInstructionsDidFailWith: error)
        }
        audioPlayer?.delegate = nil
    }
    
    @objc public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        do {
            try unDuckAudio()
        } catch {
            voiceControllerDelegate?.voiceController?(self, spokenInstructionsDidFailWith: error)
        }
    }

    @objc open override func didPassSpokenInstructionPoint(notification: NSNotification) {
        let routeProgresss = notification.userInfo![RouteControllerNotificationUserInfoKey.routeProgressKey] as! RouteProgress
        locale = routeProgresss.route.routeOptions.locale
        let currentLegProgress: RouteLegProgress = routeProgresss.currentLegProgress

        let instructionSets = currentLegProgress.remainingSteps.prefix(stepsAheadToCache).compactMap { $0.instructionsSpokenAlongStep }
        let instructions = instructionSets.flatMap { $0 }
        let unfetchedInstructions = instructions.filter { !hasCachedSpokenInstructionForKey($0.ssmlText) }
        
        unfetchedInstructions.forEach( downloadAndCacheSpokenInstruction(instruction:) )
        
        super.didPassSpokenInstructionPoint(notification: notification)
    }

    /**
     Speaks an instruction.
     
     The cache is first checked to see if we have already downloaded the speech file. If not, the instruction is fetched and played. If there is an error anywhere along the way, the instruction will be spoken with the default speech synthesizer.
     */
    @objc open override func speak(_ instruction: SpokenInstruction) {
        if let audioPlayer = audioPlayer, audioPlayer.isPlaying, let lastSpokenInstruction = lastSpokenInstruction {
            voiceControllerDelegate?.voiceController?(self, didInterrupt: lastSpokenInstruction, with: instruction)
        }
        
        audioTask?.cancel()
        audioPlayer?.stop()
        
        assert(routeProgress != nil, "routeProgress should not be nil.")
        
        guard let _ = routeProgress!.route.speechLocale else {
            speakWithDefaultSpeechSynthesizer(instruction, error: nil)
            return
        }
        
        let modifiedInstruction = voiceControllerDelegate?.voiceController?(self, willSpeak: instruction, routeProgress: routeProgress!) ?? instruction
        lastSpokenInstruction = modifiedInstruction

        if let data = cachedDataForKey(modifiedInstruction.ssmlText) {
            play(data)
            return
        }
        
        fetchAndSpeak(instruction: modifiedInstruction)
    }

    /**
     Speaks an instruction with the built in speech synthesizer.
     
     This method should be used in cases where `fetch(instruction:)` or `play(_:)` fails.
     */
    @objc open func speakWithDefaultSpeechSynthesizer(_ instruction: SpokenInstruction, error: Error?) {
        audioTask?.cancel()
        
        if let error = error {
            voiceControllerDelegate?.voiceController?(self, spokenInstructionsDidFailWith: error)
        }
        
        guard let audioPlayer = audioPlayer else {
            super.speak(instruction)
            return
        }
        
        guard !audioPlayer.isPlaying else { return }
        
        super.speak(instruction)
    }
    
    /**
     Fetches and plays an instruction.
     */
    @objc open func fetchAndSpeak(instruction: SpokenInstruction) {
        audioTask?.cancel()
        let ssmlText = instruction.ssmlText
        let options = SpeechOptions(ssml: ssmlText)
        if let locale = locale {
            options.locale = locale
        }
        
        audioTask = speech.audioData(with: options) { [weak self] (data, error) in
            guard let strongSelf = self else { return }
            if let error = error as? URLError, error.code == .cancelled {
                return
            } else if let error = error {
                strongSelf.speakWithDefaultSpeechSynthesizer(instruction, error: error)
                return
            }
            
            guard let data = data else {
                strongSelf.speakWithDefaultSpeechSynthesizer(instruction, error: NSError(code: .spokenInstructionFailed, localizedFailureReason: strongSelf.localizedErrorMessage, spokenInstructionCode: .emptyMapboxSpeechResponse))
                return
            }
            strongSelf.play(data)
            strongSelf.cache(data, forKey: ssmlText)
        }
        
        audioTask?.resume()
    }

    /**
     Caches an instruction in an in-memory cache.
     */
    @objc open func downloadAndCacheSpokenInstruction(instruction: SpokenInstruction) {
        let ssmlText = instruction.ssmlText
        let options = SpeechOptions(ssml: ssmlText)
        if let locale = locale {
            options.locale = locale
        }
        
        if let locale = routeProgress?.route.speechLocale {
            options.locale = locale
        }

        speech.audioData(with: options) { [weak self] (data, error) in
            guard let data = data else {
                return
            }
            self?.cache(data, forKey: ssmlText)
        }
    }

    private func cache(_ data: Data, forKey key: String) {
        cache.store(data, forKey: key, toDisk: true, completion: nil)
    }

    internal func cachedDataForKey(_ key: String) -> Data? {
        return cache.data(forKey: key)
    }

    internal func hasCachedSpokenInstructionForKey(_ key: String) -> Bool {
        return cachedDataForKey(key) != nil
    }

    /**
     Plays an audio file.
     */
    @objc open func play(_ data: Data) {

        super.speechSynth.stopSpeaking(at: .immediate)
        
        audioQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            do {
                strongSelf.audioPlayer = try strongSelf.audioPlayerType.init(data: data)
                strongSelf.audioPlayer?.prepareToPlay()
                strongSelf.audioPlayer?.delegate = strongSelf
                try strongSelf.duckAudio()
                let played = strongSelf.audioPlayer?.play() ?? false
                
                guard played else {
                    try strongSelf.unDuckAudio()
                    strongSelf.speakWithDefaultSpeechSynthesizer(strongSelf.lastSpokenInstruction!, error: NSError(code: .spokenInstructionFailed, localizedFailureReason: strongSelf.localizedErrorMessage, spokenInstructionCode: .audioPlayerFailedToPlay))
                    return
                }
                
            } catch  let error as NSError {
                strongSelf.speakWithDefaultSpeechSynthesizer(strongSelf.lastSpokenInstruction!, error: error)
            }
        }
    }
}
