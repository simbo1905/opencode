-- Explicit Continuation and Traversal Stability Tests
-- Tests app/traversal.lua: validate, query_opts, bounds

package.path = "./app/?.lua;" .. package.path
local traversal = require("traversal")

-- ──────────────────────────────────────────────
-- M.validate
-- ──────────────────────────────────────────────
describe("traversal.validate", function()

  -- ── nil / missing params ──
  it("returns error when params is nil", function()
    local p, err = traversal.validate(nil)
    assert.is_nil(p)
    assert.are.equal("params required", err)
  end)

  -- ── limit defaults ──
  it("defaults limit to 50 when omitted", function()
    local p = traversal.validate({})
    assert.are.equal(50, p.limit)
  end)

  it("accepts explicit limit within range", function()
    local p = traversal.validate({limit = 1})
    assert.are.equal(1, p.limit)

    local p2 = traversal.validate({limit = 1000})
    assert.are.equal(1000, p2.limit)

    local p3 = traversal.validate({limit = 25})
    assert.are.equal(25, p3.limit)
  end)

  -- ── limit out-of-range ──
  it("rejects limit = 0", function()
    local p, err = traversal.validate({limit = 0})
    assert.is_nil(p)
    assert.matches("limit must be a number between 1 and 1000", err)
  end)

  it("rejects limit = -1", function()
    local p, err = traversal.validate({limit = -1})
    assert.is_nil(p)
    assert.matches("limit must be", err)
  end)

  it("rejects limit = 1001", function()
    local p, err = traversal.validate({limit = 1001})
    assert.is_nil(p)
    assert.matches("limit must be", err)
  end)

  it("rejects non-numeric limit", function()
    local p, err = traversal.validate({limit = "fifty"})
    assert.is_nil(p)
    assert.matches("limit must be", err)
  end)

  -- ── direction defaults ──
  it("defaults direction to descending", function()
    local p = traversal.validate({})
    assert.are.equal("descending", p.direction)
  end)

  it("accepts ascending direction", function()
    local p = traversal.validate({direction = "ascending"})
    assert.are.equal("ascending", p.direction)
  end)

  it("accepts descending direction", function()
    local p = traversal.validate({direction = "descending"})
    assert.are.equal("descending", p.direction)
  end)

  it("rejects invalid direction", function()
    local p, err = traversal.validate({direction = "sideways"})
    assert.is_nil(p)
    assert.matches("direction must be", err)
  end)

  -- ── continuation anchors ──
  it("rejects continuation without any anchor", function()
    local p, err = traversal.validate({is_continuation = true})
    assert.is_nil(p)
    assert.matches("continuation requires explicit anchor", err)
  end)

  it("accepts continuation with time_window_start", function()
    local p = traversal.validate({
      is_continuation = true,
      time_window_start = "2025-01-01T00:00:00Z",
    })
    assert.is_not_nil(p)
    assert.are.equal("2025-01-01T00:00:00Z", p.time_window_start)
  end)

  it("accepts continuation with time_window_end", function()
    local p = traversal.validate({
      is_continuation = true,
      time_window_end = "2025-06-01T00:00:00Z",
    })
    assert.is_not_nil(p)
    assert.are.equal("2025-06-01T00:00:00Z", p.time_window_end)
  end)

  it("accepts continuation with anchor_message_id", function()
    local p = traversal.validate({
      is_continuation = true,
      anchor_message_id = "msg_xyz",
    })
    assert.is_not_nil(p)
    assert.are.equal("msg_xyz", p.anchor_message_id)
  end)

  it("accepts first request with no anchors (not a continuation)", function()
    local p = traversal.validate({})
    assert.is_not_nil(p)
  end)

  -- ── returned fields ──
  it("passes through all fields in returned table", function()
    local p = traversal.validate({
      limit = 10,
      direction = "ascending",
      time_window_start = "a",
      time_window_end = "b",
      anchor_message_id = "c",
      mailbox_id = "d",
    })
    assert.are.equal(10, p.limit)
    assert.are.equal("ascending", p.direction)
    assert.are.equal("a", p.time_window_start)
    assert.are.equal("b", p.time_window_end)
    assert.are.equal("c", p.anchor_message_id)
    assert.are.equal("d", p.mailbox_id)
  end)

  it("does not carry unknown fields into the returned table", function()
    local p = traversal.validate({extra_field = "leaked"})
    assert.is_nil(p.extra_field)
    assert.is_nil(p.is_continuation)
  end)
end)

-- ──────────────────────────────────────────────
-- M.query_opts
-- ──────────────────────────────────────────────
describe("traversal.query_opts", function()

  it("sets limit from params", function()
    local p = traversal.validate({limit = 20})
    local opts = traversal.query_opts(p)
    assert.are.equal(20, opts.limit)
  end)

  it("sets sort isAscending=false for descending", function()
    local p = traversal.validate({direction = "descending"})
    local opts = traversal.query_opts(p)
    assert.is_false(opts.sort[1].isAscending)
    assert.are.equal("receivedAt", opts.sort[1].property)
  end)

  it("sets sort isAscending=true for ascending", function()
    local p = traversal.validate({direction = "ascending"})
    local opts = traversal.query_opts(p)
    assert.is_true(opts.sort[1].isAscending)
  end)

  it("sets after from time_window_start", function()
    local p = traversal.validate({time_window_start = "2025-01-01T00:00:00Z"})
    local opts = traversal.query_opts(p)
    assert.are.equal("2025-01-01T00:00:00Z", opts.after)
  end)

  it("sets before from time_window_end", function()
    local p = traversal.validate({time_window_end = "2025-06-01T00:00:00Z"})
    local opts = traversal.query_opts(p)
    assert.are.equal("2025-06-01T00:00:00Z", opts.before)
  end)

  it("omits after when time_window_start not set", function()
    local p = traversal.validate({})
    local opts = traversal.query_opts(p)
    assert.is_nil(opts.after)
  end)

  it("omits before when time_window_end not set", function()
    local p = traversal.validate({})
    local opts = traversal.query_opts(p)
    assert.is_nil(opts.before)
  end)

  it("returns identical opts for identical params (stability)", function()
    local p = traversal.validate({
      limit = 30,
      direction = "ascending",
      time_window_start = "2025-03-01T00:00:00Z",
    })
    local o1 = traversal.query_opts(p)
    local o2 = traversal.query_opts(p)
    assert.same(o1, o2)
  end)
end)

-- ──────────────────────────────────────────────
-- M.bounds
-- ──────────────────────────────────────────────
describe("traversal.bounds", function()

  local function make_params(overrides)
    return traversal.validate(overrides or {})
  end

  -- ── empty results ──
  it("returns count=0, has_more=false for nil emails", function()
    local b = traversal.bounds(nil, make_params())
    assert.are.equal(0, b.count)
    assert.is_false(b.has_more)
  end)

  it("returns count=0, has_more=false for empty list", function()
    local b = traversal.bounds({}, make_params())
    assert.are.equal(0, b.count)
    assert.is_false(b.has_more)
  end)

  it("does not include next_page when empty", function()
    local b = traversal.bounds({}, make_params())
    assert.is_nil(b.next_page)
  end)

  -- ── non-empty descending ──
  it("reports correct count for non-empty results", function()
    local emails = {
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 50}))
    assert.are.equal(2, b.count)
  end)

  it("identifies oldest and newest entries (descending)", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params())
    assert.are.equal("e3", b.newest_id)
    assert.are.equal("e1", b.oldest_id)
    assert.are.equal("2025-01-03", b.newest_received_at)
    assert.are.equal("2025-01-01", b.oldest_received_at)
  end)

  it("sets has_more=true when count equals limit", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 3}))
    assert.is_true(b.has_more)
  end)

  it("sets has_more=false when count is less than limit", function()
    local emails = {
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 50}))
    assert.is_false(b.has_more)
  end)

  -- ── descending next_page ──
  it("builds descending next_page with time_window_end = oldest receivedAt", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 3}))
    assert.are.equal("descending", b.next_page.direction)
    assert.are.equal("2025-01-01", b.next_page.time_window_end)
  end)

  -- ── ascending next_page ──
  it("builds ascending next_page with time_window_start = newest receivedAt", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 3, direction = "ascending"}))
    assert.are.equal("ascending", b.next_page.direction)
    assert.are.equal("2025-01-03", b.next_page.time_window_start)
  end)

  -- ── single email ──
  it("handles single-element email list", function()
    local emails = {{id = "only", receivedAt = "2025-06-15"}}
    local b = traversal.bounds(emails, make_params({limit = 50}))
    assert.are.equal(1, b.count)
    assert.is_false(b.has_more)
    assert.are.equal("only", b.newest_id)
    assert.are.equal("only", b.oldest_id)
    assert.are.equal("2025-06-15", b.newest_received_at)
    assert.are.equal("2025-06-15", b.oldest_received_at)
  end)

  -- ── pagination round-trip ──
  it("next_page can be used as input for a valid continuation", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 3}))
    -- Use next_page to build a continuation request
    local p2 = traversal.validate({
      time_window_end = b.next_page.time_window_end,
      direction = b.next_page.direction,
      is_continuation = true,
    })
    assert.is_not_nil(p2)
    assert.are.equal("2025-01-01", p2.time_window_end)
    assert.are.equal("descending", p2.direction)
  end)

  it("ascending next_page can be used as input for a valid continuation", function()
    local emails = {
      {id = "e3", receivedAt = "2025-01-03"},
      {id = "e2", receivedAt = "2025-01-02"},
      {id = "e1", receivedAt = "2025-01-01"},
    }
    local b = traversal.bounds(emails, make_params({limit = 3, direction = "ascending"}))
    local p2 = traversal.validate({
      time_window_start = b.next_page.time_window_start,
      direction = b.next_page.direction,
      is_continuation = true,
    })
    assert.is_not_nil(p2)
    assert.are.equal("2025-01-03", p2.time_window_start)
    assert.are.equal("ascending", p2.direction)
  end)
end)
