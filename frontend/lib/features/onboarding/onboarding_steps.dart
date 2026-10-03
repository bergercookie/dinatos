/// Where a step's card sits.
enum CardPlacement {
  /// Next to the target, on whichever side has room.
  auto,

  /// Docked to the top of the screen, whatever the target.
  screenTop,

  /// Docked to the bottom of the screen (clear of the navigation bar). For a
  /// step whose target has the thing to fill in or press next right beside it:
  /// the card then sits in empty space instead of on top of that.
  screenBottom,
}

/// Raised once the user's profile has been saved.
const profileSavedEvent = 'profile-saved';

/// One card of the first-run tour. See `onboarding_controller.dart` for how
/// a step is entered and left, and `onboarding_overlay.dart` for how it is
/// drawn.
class TourStep {
  const TourStep({
    required this.id,
    required this.title,
    required this.body,
    this.target,
    this.advanceOnEvent,
    this.advanceOnLocation,
    this.modal = false,
    this.cardPlacement = CardPlacement.auto,
    this.primaryLabel,
  });

  /// Stable name, also what e2e tests and logs refer to the step by.
  final String id;
  final String title;
  final String body;

  /// The `OnboardingTarget` id to highlight. Null for a centered card with
  /// nothing pointed at (the welcome and the closing one).
  final String? target;

  /// The tour moves on by itself once the app reports this event (see
  /// `OnboardingController.event`): for steps whose control doesn't navigate
  /// anywhere, like saving a form. Deliberately not "the user pressed the
  /// highlighted widget": a press reaches the app as a pointer event only for
  /// a mouse or finger, not for assistive technology, which activates a
  /// control with a semantic tap instead -- an event the app raises itself
  /// when the thing actually happened works for both.
  final String? advanceOnEvent;

  /// ...or once the app navigates to a path this accepts.
  final bool Function(String path)? advanceOnLocation;

  /// Whether everything outside the highlighted target is dimmed *and*
  /// blocks taps. Used for single-tap steps, where there is exactly one
  /// right thing to press; steps where the user has to fill something in
  /// (a dropdown menu, a picker sheet -- all rendered by the app's own
  /// navigator, underneath this overlay) must stay non-modal.
  final bool modal;

  /// Where the card goes relative to the target.
  final CardPlacement cardPlacement;

  /// A button label that advances the tour by hand ("Next", "Start tour").
  /// Null for a step that only moves on when the user does what it says.
  final String? primaryLabel;
}

/// The default first-run tour: pick units, save a first routine, then log
/// a first workout -- the three things a new account needs before the rest
/// of the app starts to make sense.
final List<TourStep> defaultTourSteps = [
  const TourStep(
    id: 'welcome',
    title: 'Welcome to Dinatos',
    body:
        "Let's take a one-minute tour: set your units, build a first routine and log a "
        'first workout. You can skip any step, or the whole tour, at any time.',
    primaryLabel: 'Start tour',
  ),
  TourStep(
    id: 'tab-profile',
    title: 'Start with your profile',
    body: 'Tap Profile to choose how weights are shown.',
    target: 'tab-profile',
    advanceOnLocation: (path) => path.startsWith('/profile'),
    modal: true,
  ),
  const TourStep(
    id: 'profile-prefs',
    title: 'Pick your units',
    body: 'Choose your unit system, add your height if you like, then press Save.',
    target: 'profile-prefs',
    advanceOnEvent: profileSavedEvent,
  ),
  TourStep(
    id: 'tab-routines',
    title: 'Routines are reusable plans',
    body:
        'A routine is a saved plan to reuse every session. You start with a few classics '
        '(Push, Pull, Legs...); tap Routines to see them and build your own.',
    target: 'tab-routines',
    advanceOnLocation: (path) => path == '/routines',
    modal: true,
  ),
  TourStep(
    id: 'routines-new',
    title: 'Create a routine',
    body: 'Press + to build a routine of your own (or skip this step to use a starter one).',
    target: 'routines-new',
    advanceOnLocation: (path) => path == '/routines/new',
    modal: true,
  ),
  TourStep(
    id: 'routine-form',
    title: 'Name it and add exercises',
    body:
        'Give the routine a name, press Add exercise to pick from the catalog, and set the '
        'sets, reps and weights you plan to do. Press Create when it looks right.',
    target: 'routine-add-exercise',
    cardPlacement: CardPlacement.screenBottom,
    advanceOnLocation: (path) => path == '/routines',
  ),
  TourStep(
    id: 'tab-home',
    title: 'Now, go train',
    body: 'Tap Home, where your workouts live.',
    target: 'tab-home',
    advanceOnLocation: (path) => path == '/activities',
    modal: true,
  ),
  TourStep(
    id: 'start-workout',
    title: 'Start a live workout',
    body: 'Press Start workout to get a running clock and log sets as you do them.',
    target: 'start-workout',
    advanceOnLocation: (path) => path == '/activities/live',
    modal: true,
  ),
  const TourStep(
    id: 'live-add-exercise',
    title: 'Add an exercise',
    body: 'Press Add exercise, pick one, then add a set and enter the weight and reps.',
    target: 'live-add-exercise',
    cardPlacement: CardPlacement.screenTop,
    primaryLabel: 'Next',
  ),
  TourStep(
    id: 'live-finish',
    title: 'Finish when you are done',
    body: 'Press Finish workout to save it and see how it went.',
    target: 'live-finish',
    advanceOnLocation: (path) => path == '/activities/live/summary',
    modal: true,
  ),
  const TourStep(
    id: 'done',
    title: "You're all set",
    body:
        'Your workout shows up under Home, with your training calendar and streak. Coming '
        'from Hevy? Profile has an importer for your history. You can replay this tour from '
        'Profile any time.',
    primaryLabel: 'Finish',
  ),
];
