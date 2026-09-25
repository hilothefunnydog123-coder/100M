# Jobwalk business plan

> Working draft. Numbers marked *assumption* are to be checked in customer
> interviews and the beta; nothing here has been validated with paying
> customers yet.

## The one-liner

Jobwalk turns a walkthrough into an approved quote: snap the job, get an
itemized quote priced with your own rates, text the link, and the customer
approves and pays a deposit from their phone.

## The problem

Owners of small home-service crews (1 to 10 people) do their quotes at
night, in the truck, on paper or in a spreadsheet. It's slow, it's
inconsistent, and it's where they lose money: underpriced jobs, forgotten
line items, and quotes that go out days later. Homeowners tend to hire
whoever gets back to them first with a clear number, so a slow quote often
means a lost job (*assumption*: widely reported by contractors; confirm in
interviews).

Field-service software (Jobber, Housecall Pro, ServiceTitan) covers
scheduling, invoicing, and payments, but building the quote is still
manual line entry. Trade-specific tools exist (PaintScout for painters;
Hover and Roofr for measurements), but none go from phone photos to a
priced, sendable quote in a minute across walkthrough trades.

## The product

- **Photo to draft.** Claude Opus 5.5 measures the job from photos, scopes
  it, and estimates hours and materials.
- **Your prices.** Deterministic code prices every line with the
  contractor's labor rate, markup, minimum job, and price list. Prices they
  type over a draft are learned.
- **Options that sell up.** Drafts come with good/better/best options
  (paint grade, pine vs cedar, wash vs wash-and-seal) where the job has a
  real choice.
- **Check before sending.** The assumptions that move the price (ceiling
  height, fence length) are flagged for the contractor to confirm.
- **A link, not a PDF.** The customer picks an option, signs, and pays the
  deposit through the contractor's payment link. The contractor sees views
  and approvals, and can nudge.
- **Built-in viral loop.** Every customer page says "Sent with Jobwalk."

## Beachhead: residential painters

Painting first, then fencing and pressure washing (all three have sample
jobs in the app today):

- Lots of small companies, most run by the owner.
- Estimating is geometry plus production rates, which photos support well.
- Natural options (paint grade, walls vs walls and trim vs full room).
- A clear buyer who already pays for software and supplies.

## Business model

| Plan | Price | For |
|---|---|---|
| Beta | Free | The first cohort, in exchange for feedback and past-job data |
| Founding | $49/mo, locked | Beta crews who convert |
| Pro | $79/mo per company | Unlimited quotes, up to 3 users |
| Crew | $149/mo | More users, team features (later) |

Take rate: customers can pay deposits by card through Stripe Connect;
Jobwalk keeps 1% of each deposit (card fees are passed through). Later:
customer-financing referral fees on larger jobs, and supplier
partnerships.

**The $10M target in plain math:** $10M ARR at $79/month is about 10,500
paying crews. Painting alone has far more small companies than that in the
US (*assumption*: size it from Census County Business Patterns and
Nonemployer Statistics for NAICS 238320 before fundraising).

## Unit economics

*Assumption, to be replaced with real numbers from server logs; each draft
logs its tokens and estimated cost.*

- A draft with 6 photos at high effort: roughly 20k input tokens and 10k
  output tokens including thinking, about $0.28 at Opus 5.5 list prices
  ($4 / $20 per million tokens), less with prompt caching.
- A crew sending 40 quotes a month: about $11/month in AI cost, which leaves
  roughly 85% gross margin on $79 before hosting and support.
- Target customer acquisition cost under $250, paid back in 3 to 4 months.

## Go to market: the first 90 days

**Weeks 1-2: talk and collect.** 20 interviews with painting company
owners (Facebook groups, supply-house counters in the morning, PDCA
chapters). Ask for 30+ past jobs with walkthrough photos and the final
price; that becomes the accuracy set.

**Weeks 3-4: private beta.** TestFlight and Play internal testing with 10
crews. Watch every quote: time from first photo to sent, how much they
change the draft, approval rate.

**Month 2: sharpen and spread.** Tune the painting prompt and production
rates against the eval set. Short videos of real "quote in 60 seconds"
walkthroughs for contractor TikTok and YouTube. The landing page waitlist
is live at `/`.

**Month 3: charge.** Convert beta crews to Founding. Goal: 50 paying crews
(about $3k MRR). Open fencing and pressure washing.

## What we measure

- **North star:** quotes approved through Jobwalk per week.
- **Accuracy:** how much contractors change the draft before sending (the
  app records the AI's total and the sent total), and the eval harness's
  median error against real invoices.
- **Speed:** minutes from first photo to sent.
- **Activation:** first quote sent within 24 hours of install.
- **Retention:** crews sending at least one quote a week.

## Risks

| Risk | Mitigation |
|---|---|
| Drafts aren't accurate enough to trust | The contractor approves every number; prices come from their rates; assumptions are flagged; eval sets per trade gate prompt changes |
| AI cost rises or latency annoys | Effort is configurable; prompt caching; cheaper models for simple trades, chosen by eval |
| Field-service suites add AI quoting | Move faster on the walkthrough-to-approval loop; price memory and per-trade tuning compound; integrate rather than compete on scheduling |
| App store rules on subscriptions | Sell plans on the web; keep the app free to download |
| Data lives on the phone in the MVP | Accounts and sync are next on the roadmap |

## What's built

- Flutter app: setup, capture with sample jobs, AI draft, quote editor,
  options, send by text or email, customer preview, status tracking,
  settings with a learned price list.
- Server: Claude drafting with structured output, quote links, the
  customer approval page, landing page with waitlist, accuracy harness.
- 169 automated tests across the three packages (73 core, 77 server, 19 app).

## Next

1. Accounts and sync, so quotes aren't tied to one phone.
2. Built-in deposits (Stripe Connect) and automatic follow-up nudges.
3. Logo and colors on the customer page; PDF export.
4. Trade packs: tuned prompts and eval sets per trade.
5. Export to QuickBooks and Jobber.
