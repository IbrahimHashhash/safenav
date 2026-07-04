class VoiceConstants {
  VoiceConstants._();

  static const navigateTriggers = [
    'navigate', 'go', 'take', 'direct', 'directions',
    'get', 'head', 'bring', 'lead', 'show',
  ];

  static const fillerWords = [
    'to', 'me', 'can', 'you', 'please', 'i', 'want',
    'need', 'would', 'like', 'could', 'the', 'a', 'an',
  ];

  static const moreInfoTriggers = [
    'info', 'help', 'commands',
  ];

  static const repeatTriggers = [
    'repeat', 'again',
  ];
  
  static const listTriggers = [
    'list', 'locations', 'location', 'places', 'place',
  ];

  static const startNavigationTriggers = [
    'start', 'begin', 'commence', 'enable', 'on',
  ];

  static const stopNavigationTriggers = [
    'stop', 'cancel', 'end', 'quit', 'halt', 'disable', 'off',
  ];

  static const detectionTriggers = [
    'detection', 'obstacle', 'obstacles', 'detect',
  ];

  static const nextInstructionTriggers = [
    'next', 'continue', 'proceed',
  ];

  static const greetingTriggers = [
    'hi', 'hello', 'hey', 'hiya', 'howdy', 'greetings', 'helo', 'hii',
    'morning', 'afternoon', 'evening',
  ];

  /// Verbs that, together with "name" (or the standalone "rename"), request a
  /// name change, e.g. "change my name", "update my name", "rename me".
  static const changeNameTriggers = [
    'change', 'rename', 'update', 'reset', 'edit',
  ];

  static const nameWordTriggers = ['name'];
}