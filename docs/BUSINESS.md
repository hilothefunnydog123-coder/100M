# Jobwalk business plan

> Working draft. Numbers marked *assumption* are to be checked in customer
> interviews and the beta; nothing here has been validated with paying
> customers yet.

## The one-liner

Jobwalk turns a walkthrough into an approved quote: snap the job, get an
itemized quote priced with your own rates, text the link, and the customer
approves and pays a deposit from their phone.

## The shape of the business

Bootstrapped and owned 100% by its founder: no investors and no equity
for anyone. It grows on its own revenue, and the goal is **$50,000 a month
in profit to the owner**. That shapes every decision:

- Costs stay variable: usage-priced AI and hosting, part-time contractors
  for support, no payroll until revenue pays for it.
- Growth is paid for out of revenue (content, referrals, affiliates), not
  with ads bought at a loss.
- Nothing that needs a sales team: crews sign up, try it, and pay by card.
- It starts as a sole proprietorship. Stripe, Apple, and Google all take
  an individual, so there's no company to form before launch. An LLC can
  come later, for liability protection and to publish under the company
  name (both stores move the apps over).

## The problem

Owners of small home-service crews (1 to 10 people) do their quotes at
night, in the truck, on paper or in a spreadsheet. It's slow, it's
inconsistent, and it's where they lose money: underpriced jobs, forgotten
line items, and quotes that go out days later. Homeowners tend to hire
whoever gets back to them first with a clear number, so a slow quote often
means a lost job (*assumption*: widely reported by contractors; confirm in
interviews).

## The product

- **Photo to draft.** An AI model measures the job from photos, scopes it,
  and estimates hours and materials. The model is a setting (Claude,
  Gemini, or Groq), chosen by accuracy on real jobs and by cost.
- **Your prices.** Deterministic code prices every line with the
  contractor's labor rate, markup, minimum job, and price list. Prices they
  type over a draft are learned.
- **Options that sell up.** Drafts come with good/better/best options
  (paint grade, pine vs cedar, wash vs wash-and-seal) where the job has a
  real choice.
- **Check before sending.** The assumptions that move the price (ceiling
  height, fence length) are flagged for the contractor to confirm.
- **Write it yourself.** A quote can always be written by hand, free, with
  one-tap lines from the price list.
- **A link, not a PDF.** The customer picks an option, signs, and pays the
  deposit by card. The contractor sees views and approvals.
- **Built-in viral loop.** Every customer page says "Sent with Jobwalk."

## Competition (September 2026)

Photo-to-quote is no longer new, so Jobwalk has to win on how it quotes,
not on the idea.

| Company | What its AI does | Price |
|---|---|---|
| QuoteIQ | Photos plus a description and 5 questions, priced at local market rates, 4-7 minutes; bundled with scheduling and invoicing. Strongest in pressure washing. | From $29.99/mo |
| Handoff | Describe the job; priced from supplier catalogs. For remodelers. | $149-$299/mo |
| EstimationPro | Photos plus voice notes. For remodelers. | $39-$79/mo |
| Jobber | Drafts a quote from typed text; pricing is left to the user. No photo quotes. | Quotes from $49/mo |
| Housecall Pro | AI for calls and marketing, not quotes. | $59-$329/mo |
| CompanyCam | Scope of work from photos, no prices. | $19/user add-on |
| PaintScout | Painter estimating from typed room dimensions, no photo AI. | $119/seat + $99 |

Where Jobwalk wins: the contractor's own prices instead of a market
average, no questionnaire before the draft, options built into every
quote, and (once the eval runs on real jobs) published accuracy, which no
one in this category offers. Where it loses: no users yet, no scheduling
or invoicing, and the AI call itself is a commodity. So: stay the best
quoting tool for walkthrough trades, and send approved jobs into Jobber
and QuickBooks rather than competing with them.

## Beachhead: residential painters

Painting first, then fencing and pressure washing (all three have sample
jobs in the app today):

- Lots of small companies, most run by the owner.
- Estimating is geometry plus production rates, which photos support well.
- Natural options (paint grade, walls vs walls and trim vs full room).
- The gap in the market: QuoteIQ is strongest in exterior cleaning, and
  PaintScout, the painters' tool, is manual and costs $119 a seat.

## Pricing

| Plan | Price | For |
|---|---|---|
| Free | $0 | 25 AI drafts to try it; quotes written by hand are always free |
| Pro | $35/mo per company | Unlimited AI quotes (fair use: 500 a month), up to 3 people, card deposits |
| Crew | $79/mo | Up to 15 people |

Jobwalk also keeps 1% of every card deposit (card fees are passed
through). Worth adding: an annual Pro plan at $350 (two months free) for
cash up front and lower churn. Prices are server settings
(`JOBWALK_PRO_PRICE`, `JOBWALK_CREW_PRICE`) matched to the prices in
Stripe.

## The goal in plain math: $50,000 a month

Per paying crew per month on Pro (*assumptions* marked by ~):

| | |
|---|---|
| Price | $35.00 |
| Stripe: card fee (2.9% + 30¢) and Billing (0.7%) | -$1.56 |
| AI drafts: ~40 a month at ~3¢ on Gemini | -$1.20 |
| Hosting, photo storage, email | ~-$0.50 |
| Support: part-time help, ~1 person per 1,500 crews | ~-$2.00 |
| Failed payments and refunds | ~-$0.35 |
| **Contribution** | **~$29.40 (84%)** |
| Replacing churn: ~4% a month at ~$100 blended acquisition cost | ~-$4.00 |
| **Net per crew** | **~$25.40** |

At launch the fixed costs are about $60 a month: Supabase Pro ($25, the
database and photos), two small Fly.io machines for the server (~$15),
Apple's $99 a year, a domain, and email on it; Resend's free tier covers
the first emails. At scale, budget ~$1,500 a month (hosting, tools,
accounting, insurance). With that:

- **$50,000 a month before tax takes ~2,000 paying crews** (~$70,000 in
  monthly subscriptions).
- Deposits cut that: if a third of crews take card deposits (say 6 a month
  averaging $600, so $36 a month each at 1%), it's ~1,400 crews.
- Crew plans raise the average: 15% of customers on Crew makes the
  average ~$41.60 a month.
- **$50,000 a month after tax** needs ~$75,000-$80,000 in profit: ~3,000
  crews, or ~2,100 with deposits. An S-corp election once profitable can
  lower self-employment tax (a question for an accountant).
- For comparison, at $79 a month the same goal takes ~770 crews.

Growth math: at 4% monthly churn, holding 2,000 crews takes 80 new paying
crews every month, and reaching 2,000 in two years takes ~130 a month,
which at 20-30% trial conversion is ~450-650 sign-ups a month.

AI cost decides the model at this price: Claude Opus runs ~28¢ a draft,
~$11 a crew a month (a third of revenue), while Gemini runs ~3¢. Use
Gemini's paid API or a cheaper Claude model, chosen on real-job accuracy;
with Opus, lower the fair-use cap.

## Getting customers without investors

- **Film real quotes.** 60-second "walk it, snap it, sent" videos from
  real jobs for TikTok, Reels, Shorts, and YouTube. Free, and they keep
  working.
- **Contractor communities.** Facebook groups, trade subreddits, PDCA
  chapters: answer questions and show real quotes.
- **Affiliates.** 20-30% recurring commission to trade coaches and
  YouTubers, paid out of revenue instead of equity.
- **Referrals.** A free month for both the crew that refers and the crew
  that joins.
- **Supply houses.** QR-code flyers at paint-store counters, where painters
  are at 6-7 a.m.
- **Search.** Pages per trade and city ("painting estimate app",
  "fence quote template").

## Go to market: the first 90 days

**Weeks 1-2: talk and collect.** 20 interviews with painting company
owners (Facebook groups, supply-house counters in the morning, PDCA
chapters). Ask for 30+ past jobs with walkthrough photos and the final
price; that becomes the accuracy set.

**Weeks 3-4: private beta.** TestFlight and Play internal testing with 10
crews. Watch every quote: time from first photo to sent, how much they
change the draft, approval rate.

**Month 2: sharpen and spread.** Tune the painting prompt and production
rates against the eval set, and pick the AI model. Start the video and
community channels. The landing page waitlist is live at `/`.

**Month 3: charge.** Move beta crews to Pro at $35 (first month free as
thanks). Goal: 50 paying crews (~$1,750 a month). Open fencing and
pressure washing.

## What we measure

- **North star:** quotes approved through Jobwalk per week.
- **Accuracy:** how much contractors change the draft before sending (the
  app records the AI's total and the sent total), and the eval harness's
  median error against real invoices.
- **Speed:** minutes from first photo to sent.
- **Activation:** first quote sent within 24 hours of install.
- **Retention:** crews sending at least one quote a week, and monthly
  churn (the number the $50,000 goal is most sensitive to).

## Risks

| Risk | Mitigation |
|---|---|
| Drafts aren't accurate enough to trust | The contractor approves every number; prices come from their rates; assumptions are flagged; eval sets per trade gate prompt changes |
| QuoteIQ, Jobber, or Housecall Pro wins the category | Own one trade (painters) first; quote from the crew's own prices; publish accuracy; send jobs into Jobber and QuickBooks instead of fighting them |
| Churn at small-business rates (3-7% a month) | Annual plans, price memory that gets better with use, crew sync that makes it the team's tool |
| AI cost rises or latency annoys | The model is a setting; cheaper models chosen by eval; fair-use cap |
| App store rules on subscriptions | Sell plans on the web; iOS in the US storefront (see STORE.md) |
| One owner, one point of failure | Hosted services, automated tests and deploys, part-time help for support |
| Personal liability as a sole proprietor | Terms that cap liability; an LLC and business insurance once revenue starts |

## What's built

- App (iOS, Android, web): email sign-in, setup, capture with sample jobs,
  AI draft or write-it-yourself, quote editor with options and price-list
  lines, send by text or email, customer preview, status tracking, crew
  sync, plans, and card deposits.
- Server: accounts and sync, AI drafting with Claude, Gemini, or Groq, the
  customer page with signature record and deposits, Stripe billing and
  Connect, email, privacy policy and terms, and the accuracy harness.
- Store listing text, screenshots, and privacy answers (STORE.md).
- About 350 automated tests across the three packages.

## Next

1. Accuracy on real painting jobs, then pick the AI model.
2. The beta with 5-10 crews.
3. Send approved jobs to Jobber and QuickBooks.
4. Logo and colors on the customer page; PDF export.
5. Trade packs: tuned prompts and eval sets per trade.
