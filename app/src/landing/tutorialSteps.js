/**
 * tutorialSteps.js
 * Data layer for the scroll tutorial. Each persona has 5 steps.
 * calloutTarget: { x, y } as % of the device dimensions (top-left origin).
 * screenId: maps to a rendered screen component.
 */

export const PERSONAS = [
  {
    id: 'patient',
    label: 'Patient',
    icon: '🧑',
    device: 'phone', // 'phone' | 'laptop'
    steps: [
      {
        id: 'pat-1',
        num: '01',
        calloutLabel: 'Tap "Start"',
        calloutSide: 'right', // which side the callout appears
        calloutTarget: { x: 55, y: 74 }, // % of device width/height
        caption: 'You arrive at your nearby clinic. No specialist trip needed.',
        screenId: 'patient-walkin',
      },
      {
        id: 'pat-2',
        num: '02',
        calloutLabel: 'Look straight ahead',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 52 },
        caption: 'A trained health worker takes one painless photo of your eye.',
        screenId: 'patient-photo',
      },
      {
        id: 'pat-3',
        num: '03',
        calloutLabel: 'Your result',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 44 },
        caption: 'You get a clear, simple result right away, in plain words.',
        screenId: 'patient-result',
      },
      {
        id: 'pat-4',
        num: '04',
        calloutLabel: 'Doctor reviewing',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 63 },
        caption: 'If something needs attention, a real doctor reviews your case.',
        screenId: 'patient-doctor',
      },
      {
        id: 'pat-5',
        num: '05',
        calloutLabel: 'Set a reminder',
        calloutSide: 'right',
        calloutTarget: { x: 80, y: 72 },
        caption: 'You leave knowing exactly what to do next and when.',
        screenId: 'patient-next',
      },
    ],
  },
  {
    id: 'worker',
    label: 'Health worker',
    icon: '🩺',
    device: 'phone',
    steps: [
      {
        id: 'wrk-1',
        num: '01',
        calloutLabel: 'Patient details',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 50 },
        caption: 'Enter a few details. It takes under a minute.',
        screenId: 'worker-add',
      },
      {
        id: 'wrk-2',
        num: '02',
        calloutLabel: 'Line up in the circle',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 52 },
        caption: 'Guide the patient to look straight ahead. The circle helps.',
        screenId: 'worker-camera',
      },
      {
        id: 'wrk-3',
        num: '03',
        calloutLabel: 'Photo checked instantly',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 38 },
        caption: "If the photo isn't good enough, you'll know straight away.",
        screenId: 'worker-check',
      },
      {
        id: 'wrk-4',
        num: '04',
        calloutLabel: 'Where VITREOUS looked',
        calloutSide: 'right',
        calloutTarget: { x: 68, y: 56 },
        caption: 'A simple result, plus a highlight showing where VITREOUS looked.',
        screenId: 'worker-result',
      },
      {
        id: 'wrk-5',
        num: '05',
        calloutLabel: 'Send to doctor',
        calloutSide: 'right',
        calloutTarget: { x: 50, y: 70 },
        caption: 'Urgent cases reach the doctor in one tap.',
        screenId: 'worker-send',
      },
    ],
  },
  {
    id: 'doctor',
    label: 'Doctor',
    icon: '👩‍⚕️',
    device: 'laptop',
    steps: [
      {
        id: 'doc-1',
        num: '01',
        calloutLabel: 'Urgent badge',
        calloutSide: 'left',
        calloutTarget: { x: 38, y: 32 },
        caption: 'The cases that need you most are always at the top.',
        screenId: 'doctor-queue',
      },
      {
        id: 'doc-2',
        num: '02',
        calloutLabel: 'Where VITREOUS looked',
        calloutSide: 'left',
        calloutTarget: { x: 30, y: 52 },
        caption: 'See the photo and exactly what VITREOUS noticed.',
        screenId: 'doctor-case',
      },
      {
        id: 'doc-3',
        num: '03',
        calloutLabel: 'Tap "Agree"',
        calloutSide: 'left',
        calloutTarget: { x: 78, y: 62 },
        caption: 'You stay in charge. Agree, or change the result.',
        screenId: 'doctor-confirm',
      },
      {
        id: 'doc-4',
        num: '04',
        calloutLabel: 'Edit referral note',
        calloutSide: 'left',
        calloutTarget: { x: 50, y: 66 },
        caption: 'A referral note is drafted for you. Edit it as you like.',
        screenId: 'doctor-refer',
      },
      {
        id: 'doc-5',
        num: '05',
        calloutLabel: 'Sign and send',
        calloutSide: 'left',
        calloutTarget: { x: 50, y: 78 },
        caption: 'One signed report goes back to the clinic and the patient.',
        screenId: 'doctor-sign',
      },
    ],
  },
];
