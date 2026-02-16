
import SwiftUI
import Combine
import Observation

@Observable
class SessionController {
    // Game State
    var isPlaying: Bool = false
    var isPaused: Bool = false
    var isGameOver: Bool = false
    
    // Timer
    var timeRemaining: TimeInterval = 0
    var duration: TimeInterval
    private var timer: AnyCancellable?
    
    // Scoring
    var score: Int = 0
    var streak: Int = 0
    var learnedCount: Int = 0
    var sessionCardGoal: Int
    
    // Dependencies
    // We could inject SmartSessionManager here if we wanted the controller to own it completely.
    // For now, we will just interact with the singleton or passed instance.
    
    init(duration: TimeInterval = 300, cardGoal: Int = 20) {
        self.duration = duration
        self.sessionCardGoal = cardGoal
        self.timeRemaining = duration
    }
    
    // MARK: - Game Lifecycle
    
    func startSession() {
        isPlaying = true
        isPaused = false
        isGameOver = false
        score = 0
        streak = 0
        timeRemaining = duration
        startTimer()
    }
    
    func pauseSession() {
        isPaused = true
        timer?.cancel()
    }
    
    func resumeSession() {
        isPaused = false
        startTimer()
    }
    
    func endSession() {
        isPlaying = false
        isGameOver = true
        timer?.cancel()
    }
    
    // MARK: - Scoring
    
    func registerSuccess() {
        score += 10 + (streak * 2)
        streak += 1
    }
    
    func registerFailure() {
        streak = 0
    }
    
    func incrementLearned() {
        learnedCount += 1
        // Check for session completion based on goal?
        if learnedCount >= sessionCardGoal {
             endSession()
        }
    }
    
    // MARK: - Unused/Placeholder
    // Audio triggers could go here
    
    // MARK: - Private
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    private func tick() {
        guard isPlaying, !isPaused else { return }
        
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            endSession()
        }
    }
}
