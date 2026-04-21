import MXLightkeeperCore
import Testing

@Test func retryPolicyUsesImmediateAttemptThenCapsBackoff() {
  let policy = RetryPolicy(immediateAttempts: 1, baseDelaySeconds: 2, maxDelaySeconds: 10)

  #expect(policy.delaySeconds(forAttempt: 1) == 0)
  #expect(policy.delaySeconds(forAttempt: 2) == 2)
  #expect(policy.delaySeconds(forAttempt: 3) == 4)
  #expect(policy.delaySeconds(forAttempt: 5) == 10)
}
