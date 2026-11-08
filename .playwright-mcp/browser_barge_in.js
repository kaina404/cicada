// Playwright MCP: a recorded voice travels through the real browser VAD.
// The input is a controlled MediaStream, not a person or room microphone.
async (page) => {
  await page.goto('http://localhost:8000');
  await page.waitForFunction(() => wsOpen(), {}, {polling: 50});
  await page.evaluate(async () => {
    window.testAudioContext = new AudioContext({sampleRate: 16000});
    await testAudioContext.resume();
    window.testDestination = testAudioContext.createMediaStreamDestination();
    const originalGetStream = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia = async () => testDestination.stream;
    try { await init(); } finally { navigator.mediaDevices.getUserMedia = originalGetStream; }
    const audio = await (await fetch('/static/sample-question.wav')).arrayBuffer();
    window.testBuffer = await testAudioContext.decodeAudioData(audio);
    window.testEvents = [];
    window.savedTrigger = triggerBargeIn;
    triggerBargeIn = function () {
      testEvents.push({type: 'barge_in', at: performance.now(), state});
      return savedTrigger();
    };
    window.savedOnMessage = ws.onmessage;
    ws.onmessage = event => {
      testEvents.push({...JSON.parse(event.data), at: performance.now()});
      savedOnMessage(event);
    };
    document.getElementById('questionInput').value = 'When should I use StateFlow to manage Android UI state?';
    document.getElementById('questionForm').requestSubmit();
    const source = testAudioContext.createBufferSource();
    source.buffer = testBuffer;
    source.connect(testDestination);
    window.testStarted = performance.now();
    source.start();
  });
  try {
    await page.waitForFunction(() => testEvents.some(e => e.type === 'barge_in'), {}, {polling: 50, timeout: 12000});
    await page.waitForFunction(() => testEvents.some(e => e.type === 'turn_final') && state === 'listening' && pendingInterrupt === null, {}, {polling: 100, timeout: 25000});
    return await page.evaluate(() => {
      const barge = testEvents.find(e => e.type === 'barge_in');
      const ack = testEvents.find(e => e.type === 'interrupted');
      const final = testEvents.find(e => e.type === 'turn_final');
      if (!ack || ack.at < barge.at || final.at < ack.at) throw new Error('Invalid interruption ordering');
      if (!final.transcription?.toLowerCase().includes('retry safely')) throw new Error('New spoken question not transcribed: ' + JSON.stringify(final));
      return {source: 'recorded speech through real Silero VAD and MediaStream',
              detect_from_recording_start_ms: Math.round(barge.at - testStarted),
              ack_after_detection_ms: Math.round(ack.at - barge.at),
              text: messagesDiv.innerText, events: testEvents};
    });
  } finally {
    await page.evaluate(async () => {
      triggerBargeIn = savedTrigger;
      ws.onmessage = savedOnMessage;
      await myvad.destroy(); myvad = null;
      mediaStream.getTracks().forEach(track => track.stop()); mediaStream = null;
      await testAudioContext.close();
      goListening();
    });
  }
}
