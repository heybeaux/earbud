import Foundation

/// Sample library shown until the app is wired to EarBudKit. Content follows the approved
/// mockups (12–16, 22). Dates are relative to the day the app runs, so "Today" stays today.
enum FixtureData {
    struct Line: Sendable {
        var at: TimeInterval
        var text: String
        init(_ minutes: Int, _ seconds: Int, _ text: String) {
            self.at = TimeInterval(minutes * 60 + seconds)
            self.text = text
        }
    }

    struct Script: Sendable {
        var dayOffset: Int
        var hour: Int
        var minute: Int
        var duration: TimeInterval
        var title: String?
        var seed: Int
        var lines: [Line]
        var noSpeech = false
        /// For Recently Deleted: days ago it was deleted.
        var deletedDaysAgo: Int?
    }

    /// A recording still on the Fieldy, copied by the next sync.
    struct WaitingScript: Sendable {
        var minutesAgo: Int
        var duration: TimeInterval
        var seed: Int
        var lines: [Line]
        var noSpeech = false
        /// The first transcription attempt fails, to show the "Try again" path.
        var failFirstAttempt = false
    }

    struct History: Sendable {
        var dayOffset: Int
        var hour: Int
        var minute: Int
        var result: SyncHistoryItem.Result
        var count: Int
        var seconds: TimeInterval
        var message: String? = nil
    }

    /// Opus at 16 kHz in 40-byte, 20 ms frames: 2,000 bytes per second.
    static let bytesPerSecond = 2_000

    static let deviceName = "Fieldy 3A7C"
    static let deviceModel = "Fieldy 3 (FL3B)"
    static let firmware = "3.3.5"
    static let batteryPercent = 82
    static let pairedDaysAgo = 18
    static let lastSyncedTime = (hour: 13, minute: 40)

    static func m(_ minutes: Int, _ seconds: Int) -> TimeInterval { TimeInterval(minutes * 60 + seconds) }

    // MARK: Library (24 recordings)

    static let recordings: [Script] = [
        Script(dayOffset: 0, hour: 13, minute: 12, duration: m(6, 42), title: "Run club planning", seed: 3, lines: [
            Line(0, 0, "Okay, so for Saturday we meet at the seawall by the rowing club at seven, not six-thirty. It's too dark at six-thirty now."),
            Line(0, 14, "Priya said she can bring the cones and the first-aid kit again, so that's sorted."),
            Line(0, 31, "The long-run group does eighteen K, out to Prospect Point and back. Easy pace. No heroes."),
            Line(0, 52, "The ten-K group loops the lagoon twice. Marcus is pacing that one, and he's promised to actually slow down this time."),
            Line(1, 10, "Coffee after at the place on Denman. They can hold the back room for us if we tell them by Thursday."),
            Line(1, 34, "Bigger thing: the Powell River trip in November. We need a head count by next Friday for the ferry booking."),
            Line(2, 5, "And can someone please remind everyone that the group chat is for running, not for selling couches."),
            Line(2, 21, "Back to the trip. Jen's cousin has a place near Willingdon Beach that sleeps eight, so that covers most of us."),
            Line(2, 48, "If more than eight sign up, there's a campground just south of Powell River with walk-in sites. Cheap, but bring a warm bag."),
            Line(3, 16, "The run itself is the Willingdon trail loop on Saturday morning, about twelve K, then whatever people want after."),
            Line(3, 52, "New people: we had three last week. Let's pair each of them with someone for the first couple of runs."),
            Line(4, 30, "Reflective vests are in the bin in my trunk. Grab one if you don't have your own. It's dark by five now."),
            Line(5, 12, "Next month's long run might move to Sunday, because of the market on Saturdays. I'll put up a poll."),
            Line(5, 48, "Okay, I think that's everything. I'll write this up and send it round tonight."),
            Line(6, 20, "Oh, and happy birthday to Lou on Thursday. Cake is not optional."),
        ]),
        Script(dayOffset: 0, hour: 10, minute: 5, duration: m(1, 18), title: "Groceries", seed: 7, lines: [
            Line(0, 0, "Oat milk, two lemons, the good sourdough from the bakery on Main, and something for Sunday dinner."),
            Line(0, 21, "Maybe a chicken, or that squash thing we did last time. Check if we still have rice."),
            Line(0, 44, "Dish soap. Coffee filters, the number four ones. And the cat food, the salmon one, not the chicken."),
            Line(1, 2, "That's it. Don't buy more apples, we have plenty."),
        ]),
        Script(dayOffset: 0, hour: 8, minute: 47, duration: m(0, 12), title: nil, seed: 2, lines: [], noSpeech: true),
        Script(dayOffset: -1, hour: 16, minute: 30, duration: m(12, 5), title: "Call with Dana about the deck", seed: 4, lines: [
            Line(0, 0, "So the boards came in, but the stain is back-ordered until the ninth, which pushes the second coat."),
            Line(0, 22, "Dana thinks we can do the first coat this weekend if it stays dry. The forecast says Sunday is the better day."),
            Line(0, 58, "The railing posts are the other thing. Two of them are soft at the bottom, so those get replaced, not patched."),
            Line(1, 40, "She's quoting four hundred for the posts, materials included. That seems fair."),
            Line(2, 31, "We talked about lights on the steps. She can run a line from the outside outlet, but it needs a separate permit."),
            Line(3, 20, "I said let's skip the lights for now and see how the budget looks in the spring."),
            Line(4, 45, "Next step: she sends the revised quote by Monday, we sign, and she books the crew for the week after."),
            Line(6, 10, "Also, keep the dog off the boards for forty-eight hours after each coat. Paw prints are forever."),
            Line(8, 2, "She mentioned a guy who does gutters, if we ever get to that. Number's in my texts."),
            Line(10, 30, "Okay. I'll forward the quote to you when it comes in. Talk later."),
        ]),
        Script(dayOffset: -1, hour: 9, minute: 15, duration: m(2, 40), title: nil, seed: 6, lines: [
            Line(0, 0, "Gift idea for Maya: that ceramics class on Granville, the Thursday evening one. Check if it's still open."),
            Line(0, 24, "If it's full, the bookshop does gift cards, and she's been talking about that new graphic novel."),
            Line(1, 10, "Her birthday is the twentieth, so order by the fifteenth at the latest."),
            Line(1, 52, "And a card. Don't forget the card this time."),
        ]),
        Script(dayOffset: -2, hour: 18, minute: 2, duration: m(3, 55), title: "Podcast notes", seed: 8, lines: [
            Line(0, 0, "The bit about sleep and memory, the guest said most of it happens in the first half of the night."),
            Line(0, 26, "So going to bed late costs you more than waking up early. That's the opposite of what I assumed."),
            Line(1, 15, "She also said naps under twenty minutes help, and anything longer just makes you groggy."),
            Line(2, 10, "Caffeine has a half-life of about five hours, so a three o'clock coffee is still a quarter there at midnight."),
            Line(3, 5, "Worth trying: no screens for the last half hour, same wake-up time on weekends."),
        ]),
        Script(dayOffset: -2, hour: 7, minute: 20, duration: m(0, 48), title: nil, seed: 9, lines: [
            Line(0, 0, "Remember to move the car before eight, street cleaning on our side this week."),
            Line(0, 19, "And put the recycling out. Blue bin, not the green one."),
        ]),
        Script(dayOffset: -2, hour: 6, minute: 48, duration: m(4, 10), title: "Morning pages", seed: 10, lines: [
            Line(0, 0, "Slept badly again. The neighbour's heat pump kicks on at four and sounds like a small plane."),
            Line(0, 35, "Three things for today: finish the slides, call the clinic, and actually eat lunch away from the desk."),
            Line(1, 30, "I keep meaning to start running in the mornings. Maybe Monday. Maybe."),
            Line(2, 40, "The slides are mostly done. It's the last section, the numbers, that needs a clearer story."),
            Line(3, 30, "Okay. Coffee."),
        ]),
        Script(dayOffset: -2, hour: 6, minute: 31, duration: m(0, 35), title: nil, seed: 11, lines: [
            Line(0, 0, "Note to self: the dentist moved the appointment to the fourth at ten-thirty."),
            Line(0, 15, "Bring the insurance card. They said the old one expired."),
        ]),
        Script(dayOffset: -3, hour: 20, minute: 15, duration: m(5, 30), title: "Budget check-in", seed: 12, lines: [
            Line(0, 0, "Okay, October so far. Groceries are a bit over, mostly because of the party."),
            Line(0, 40, "Utilities are fine. The gas bill will go up next month with the cold."),
            Line(1, 35, "We said we'd put two hundred a month toward the trip fund. We missed September, so let's double up."),
            Line(2, 50, "The gym membership. Am I actually going? Twice in October. That's forty dollars a visit."),
            Line(4, 10, "Cancel the streaming one we never watch. Keep the other."),
        ]),
        Script(dayOffset: -3, hour: 8, minute: 5, duration: m(0, 40), title: nil, seed: 13, lines: [
            Line(0, 0, "Parking ticket. Pay it online before Friday or it doubles."),
            Line(0, 18, "The number is on the fridge."),
        ]),
        Script(dayOffset: -4, hour: 19, minute: 34, duration: m(9, 20), title: "Weekend ideas with Sam", seed: 14, lines: [
            Line(0, 0, "So the long weekend. We could do the island again, but the ferry lineups last time were brutal."),
            Line(0, 40, "Sam wants somewhere with a hot tub. I want somewhere with a trail. We can probably have both."),
            Line(1, 30, "Whistler is easy but expensive, and it'll be busy with the early ski crowd."),
            Line(2, 15, "…or we skip the city entirely and do Powell River, the cabin by Willingdon Beach if it's free that weekend."),
            Line(3, 10, "Two ferries, but the drive is beautiful, and it's quiet this time of year."),
            Line(4, 20, "Budget: the cabin is about one-sixty a night. Split two ways that's fine."),
            Line(5, 45, "Sam's going to check the dates with work. I'll message the cabin people tomorrow."),
            Line(7, 30, "And we need to sort out who feeds the cat. Ask Jen first."),
        ]),
        Script(dayOffset: -4, hour: 9, minute: 30, duration: m(3, 12), title: "Standup notes", seed: 15, lines: [
            Line(0, 0, "Standup. The release is still on for Thursday. QA found two small things, both fixed."),
            Line(0, 35, "I'm on the settings screen this week. The design is approved, so it's mostly building."),
            Line(1, 20, "Blocker: I need access to the test devices. Ask Ravi."),
            Line(2, 15, "Retro moved to Friday at two."),
        ]),
        Script(dayOffset: -5, hour: 14, minute: 20, duration: m(6, 5), title: "Mum's birthday plans", seed: 16, lines: [
            Line(0, 0, "Mum's seventieth. Everyone agrees on dinner, not a party. She'd hate a party."),
            Line(0, 45, "The Italian place on Commercial can do a table for twelve on the Saturday."),
            Line(1, 50, "Aunt Carol is flying in on Thursday, so someone needs to pick her up from the airport."),
            Line(3, 0, "Photo book: I'll collect pictures from everyone by the end of next week."),
            Line(4, 30, "Gift from all of us, the garden bench she keeps looking at. Split it eight ways."),
        ]),
        Script(dayOffset: -6, hour: 15, minute: 10, duration: m(2, 2), title: "Bike shop", seed: 17, lines: [
            Line(0, 0, "The bike shop says the rear wheel is out of true and the chain is worn."),
            Line(0, 30, "About ninety for both. Ready on Tuesday after three."),
            Line(1, 15, "They also suggested new brake pads before winter. Said yes."),
        ]),
        Script(dayOffset: -6, hour: 10, minute: 42, duration: m(1, 20), title: nil, seed: 18, lines: [
            Line(0, 0, "Saw a heron at the lagoon this morning, just standing in the shallows, completely still."),
            Line(0, 30, "There were about twenty people watching it and it didn't care at all."),
            Line(0, 58, "Should bring the good camera next time."),
        ]),
        Script(dayOffset: -7, hour: 11, minute: 30, duration: m(8, 10), title: "Car insurance call", seed: 19, lines: [
            Line(0, 0, "Calling about the renewal. The quote went up by about twelve percent this year."),
            Line(0, 50, "She said it's across the board, nothing to do with our record."),
            Line(2, 5, "If we bump the deductible to a thousand, it comes down by about eighty dollars a year."),
            Line(3, 40, "Roadside assistance is already included, so we can drop the separate plan."),
            Line(5, 30, "Renewal date is the fifteenth. She'll email the paperwork."),
            Line(7, 15, "Reference number is on the email. Don't lose it."),
        ]),
        Script(dayOffset: -8, hour: 21, minute: 5, duration: m(4, 44), title: "Book club thoughts", seed: 20, lines: [
            Line(0, 0, "Thoughts for book club. I liked the first half much more than the second."),
            Line(0, 40, "The sister is the most interesting character and she disappears for a hundred pages."),
            Line(1, 45, "The ending felt rushed, like the author ran out of time."),
            Line(2, 50, "Question for the group: was the narrator lying to us or to herself?"),
            Line(4, 5, "Next month's pick is mine. Maybe something shorter."),
        ]),
        Script(dayOffset: -9, hour: 12, minute: 10, duration: m(0, 55), title: nil, seed: 21, lines: [
            Line(0, 0, "Lunch idea: the new ramen place on Robson. Apparently the line moves fast."),
            Line(0, 25, "Go before twelve or after one-thirty."),
        ]),
        Script(dayOffset: -10, hour: 17, minute: 25, duration: m(2, 30), title: "Garden to-do", seed: 22, lines: [
            Line(0, 0, "Garden before the frost. Bring the pots in, the rosemary and the lemon tree."),
            Line(0, 35, "Cut back the tomatoes, they're done. Compost the vines."),
            Line(1, 20, "Plant the garlic. The bulbs are in the shed, in the paper bag."),
            Line(2, 0, "Leaves: rake them onto the beds, not into the bin."),
        ]),
        Script(dayOffset: -12, hour: 11, minute: 2, duration: m(1, 47), title: nil, seed: 23, lines: [
            Line(0, 0, "Ferry from Earls Cove leaves at 2:20, so if we want Powell River before dark we leave town by eleven."),
            Line(0, 28, "The second ferry is only about fifty minutes, and the first is forty. Plus the drive in between."),
            Line(0, 55, "Book the Powell River cabin for two nights, Friday and Saturday."),
            Line(1, 20, "Look up the brewery in Powell River that Jen mentioned. Something with a dog on the label."),
        ]),
        Script(dayOffset: -14, hour: 8, minute: 40, duration: m(7, 15), title: "Interview prep", seed: 24, lines: [
            Line(0, 0, "Interview prep. They'll ask about the migration project, so have the numbers ready."),
            Line(0, 55, "Story for \"a time you disagreed\": the launch date argument. Keep it short and end with what changed."),
            Line(2, 20, "Questions for them: how the team handles on-call, and what success looks like at six months."),
            Line(4, 10, "Don't forget to ask about remote days."),
            Line(5, 30, "Leave by eight-fifteen. It's the building with the green awning."),
        ]),
        Script(dayOffset: -16, hour: 19, minute: 50, duration: m(1, 5), title: nil, seed: 25, lines: [
            Line(0, 0, "The plumber is coming Thursday between eight and twelve. Someone has to be home."),
            Line(0, 30, "Move the stuff out from under the kitchen sink the night before."),
        ]),
        Script(dayOffset: -18, hour: 16, minute: 5, duration: m(0, 32), title: "Testing my new Fieldy", seed: 26, lines: [
            Line(0, 0, "Testing, testing. This is my first recording with the new Fieldy."),
            Line(0, 12, "If this shows up on my Mac with the words, it works."),
        ]),
    ]

    // MARK: Recently Deleted (2)

    static let deleted: [Script] = [
        Script(dayOffset: -2, hour: 14, minute: 31, duration: m(0, 3), title: nil, seed: 27, lines: [], noSpeech: true, deletedDaysAgo: 1),
        Script(dayOffset: -6, hour: 13, minute: 2, duration: m(0, 41), title: nil, seed: 28, lines: [], noSpeech: true, deletedDaysAgo: 3),
    ]

    // MARK: Waiting on the Fieldy (copied by the next sync)

    static let waiting: [WaitingScript] = [
        WaitingScript(minutesAgo: 108, duration: m(7, 48), seed: 5, lines: [
            Line(0, 0, "So the quote for the kitchen cabinets came in at just under eleven thousand, which is more than we said, but it includes the install."),
            Line(0, 19, "He thinks the old uppers can stay if we paint them, which would save maybe two thousand. I kind of like that idea."),
            Line(0, 41, "The countertop is the open question. Quartz is three weeks out, the butcher block he has in stock."),
            Line(1, 2, "Start date could be the sixteenth if we sign by Wednesday. I told him we'd call back after the weekend."),
            Line(1, 24, "Hardware is extra. He showed me some brass pulls that were nice, but forty dollars each is a lot."),
            Line(2, 10, "We'd need to empty the kitchen for about a week. Camping stove in the dining room, apparently."),
            Line(3, 5, "He said the permit isn't needed since nothing structural changes. Just the electrician for the under-cabinet lights."),
            Line(4, 20, "Payment is a third up front, a third at the halfway point, and the rest when it's done."),
            Line(5, 35, "I asked for two references. He'll send them tonight."),
            Line(6, 40, "Let's talk it through on Sunday and decide."),
        ]),
        WaitingScript(minutesAgo: 57, duration: m(2, 5), seed: 30, lines: [
            Line(0, 0, "Things to pick up on the way home: dry cleaning, the prescription, and stamps."),
            Line(0, 40, "The pharmacy closes at six on Fridays."),
            Line(1, 25, "And return the library books, they're due tomorrow."),
        ], failFirstAttempt: true),
        WaitingScript(minutesAgo: 5, duration: m(1, 36), seed: 31, lines: [
            Line(0, 0, "Quick one before I forget: Lou's birthday cake. Chocolate, from the bakery on Main. Pick it up Thursday after work."),
            Line(0, 35, "Candles. Seven of them is fine, nobody's counting."),
            Line(1, 5, "And a card everyone can sign at the run."),
        ]),
    ]

    // MARK: Sync history

    static let history: [History] = [
        History(dayOffset: 0, hour: 13, minute: 40, result: .success, count: 3, seconds: m(8, 12)),
        History(dayOffset: -1, hour: 21, minute: 2, result: .success, count: 2, seconds: m(14, 45)),
        History(dayOffset: -2, hour: 19, minute: 10, result: .success, count: 4, seconds: m(9, 28)),
        History(dayOffset: -3, hour: 21, minute: 30, result: .success, count: 2, seconds: m(6, 10)),
        History(dayOffset: -4, hour: 21, minute: 5, result: .success, count: 1, seconds: m(3, 12)),
        History(dayOffset: -4, hour: 20, minute: 45, result: .interrupted, count: 1, seconds: m(9, 20),
                message: "Your Fieldy went out of range. 1 recording was saved. The rest came over on the next sync."),
        History(dayOffset: -5, hour: 18, minute: 0, result: .success, count: 1, seconds: m(6, 5)),
        History(dayOffset: -6, hour: 17, minute: 30, result: .success, count: 2, seconds: m(3, 22)),
        History(dayOffset: -7, hour: 12, minute: 0, result: .success, count: 1, seconds: m(8, 10)),
        History(dayOffset: -8, hour: 22, minute: 0, result: .success, count: 1, seconds: m(4, 44)),
        History(dayOffset: -9, hour: 20, minute: 0, result: .success, count: 1, seconds: m(0, 55)),
        History(dayOffset: -10, hour: 18, minute: 0, result: .success, count: 1, seconds: m(2, 30)),
        History(dayOffset: -11, hour: 19, minute: 15, result: .nothingNew, count: 0, seconds: 0),
        History(dayOffset: -12, hour: 12, minute: 0, result: .success, count: 1, seconds: m(1, 47)),
        History(dayOffset: -14, hour: 18, minute: 0, result: .success, count: 1, seconds: m(7, 15)),
        History(dayOffset: -16, hour: 21, minute: 0, result: .success, count: 1, seconds: m(1, 5)),
        History(dayOffset: -18, hour: 16, minute: 10, result: .success, count: 1, seconds: m(0, 32)),
    ]

    // MARK: Helpers

    static func date(dayOffset: Int, hour: Int, minute: Int, reference: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: reference)
        let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func segments(_ lines: [Line], duration: TimeInterval) -> [TranscriptSegment] {
        lines.enumerated().map { index, line in
            let end = index + 1 < lines.count ? lines[index + 1].at : duration
            return TranscriptSegment(position: index, start: line.at, end: end, text: line.text)
        }
    }
}
