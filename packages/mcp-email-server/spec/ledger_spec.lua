-- Action Ledger and Delayed Action Tests
-- Derived from RFC Addendum sections A1-A6

describe("Action Ledger", function()

  pending("exposes queryable list of action events")
  pending("tracks pending, executed, cancelled, and failed actions")
  pending("links ledger entries to SessionID and OpRef")
  pending("separates scheduling and execution as distinct logged operations")

end)

describe("Delayed Actions", function()

  pending("requires explicit DelaySpec for delayed execution mode")
  pending("records DelaySpec in session log and ledger entry")
  pending("rejects delayed without DelaySpec")
  pending("ask mode returns structured proposal without executing")

end)

describe("Execution-time Revalidation", function()

  pending("revalidates preconditions at execution time")
  pending("surfaces conflicts when target message no longer exists")
  pending("surfaces conflicts when draft has been edited")

end)

describe("Idempotency and Duplicate Prevention", function()

  pending("prevents duplicate execution of delayed actions")
  pending("makes duplicate attempts visible in ledger")

end)

describe("Approval for Delayed Actions", function()

  pending("requires explicit approval scope for scheduling and execution")
  pending("does not allow delay to bypass approval requirements")
  pending("sending remains conservative under delay")

end)
