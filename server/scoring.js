/**
 * Award only the improvement above a player's previous best.
 * The first completed run grants a one-time completion bonus.
 */
export function calculateReward(correct, oldBest, firstCompletion) {
  if (!Number.isInteger(correct) || !Number.isInteger(oldBest) || correct < 0 || oldBest < 0) {
    throw new TypeError('Số câu đúng và kỷ lục phải là số nguyên không âm.');
  }
  const improvement = Math.max(0, correct - oldBest);
  return {
    xpEarned: improvement * 35 + (firstCompletion ? 60 : 0),
    coinsEarned: improvement * 10 + (firstCompletion ? 30 : 0)
  };
}
