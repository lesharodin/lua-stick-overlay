"use strict";

const video = document.getElementById("video");
const canvas = document.getElementById("overlay");
const ctx = canvas.getContext("2d");
const stage = document.getElementById("stage");
const emptyState = document.getElementById("emptyState");

const videoInput = document.getElementById("videoInput");
const csvInput = document.getElementById("csvInput");
const offsetInput = document.getElementById("offsetInput");
const scaleInput = document.getElementById("scaleInput");
const opacityInput = document.getElementById("opacityInput");
const positionInput = document.getElementById("positionInput");

const sampleCount = document.getElementById("sampleCount");
const logLength = document.getElementById("logLength");
const offsetValue = document.getElementById("offsetValue");
const scaleValue = document.getElementById("scaleValue");
const opacityValue = document.getElementById("opacityValue");
const videoTime = document.getElementById("videoTime");
const csvTime = document.getElementById("csvTime");
const armState = document.getElementById("armState");
const message = document.getElementById("message");
const exportButton = document.getElementById("exportButton");
const exportProgress = document.getElementById("exportProgress");
const downloadLink = document.getElementById("downloadLink");

const state = {
  samples: [],
  videoUrl: null,
  renderUrl: null,
  offsetMs: 0,
  scale: 1,
  opacity: 0.95,
  position: "bottom-left",
  exporting: false,
};

function setMessage(text, isError = false) {
  message.textContent = text;
  message.classList.toggle("error", isError);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function formatMs(value) {
  const sign = value > 0 ? "+" : "";
  return `${sign}${Math.round(value)} ms`;
}

function parseCsvLine(line) {
  const cells = [];
  let cell = "";
  let quoted = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === "\"" && quoted && next === "\"") {
      cell += "\"";
      index += 1;
    } else if (char === "\"") {
      quoted = !quoted;
    } else if (char === "," && !quoted) {
      cells.push(cell);
      cell = "";
    } else {
      cell += char;
    }
  }

  cells.push(cell);
  return cells;
}

function parseStickCsv(text) {
  const lines = text.replace(/\r/g, "").split("\n").filter((line) => line.trim() !== "");
  if (lines.length < 2) {
    throw new Error("CSV has no sample rows.");
  }

  const header = parseCsvLine(lines[0]).map((name) => name.trim());
  const required = ["kind", "t_ms", "roll", "pitch", "thr", "yaw", "arm"];
  const columns = Object.fromEntries(header.map((name, index) => [name, index]));
  const missing = required.filter((name) => columns[name] === undefined);

  if (missing.length > 0) {
    throw new Error(`CSV is missing: ${missing.join(", ")}`);
  }

  const samples = [];

  for (let lineIndex = 1; lineIndex < lines.length; lineIndex += 1) {
    const row = parseCsvLine(lines[lineIndex]);
    if (row[columns.kind] !== "sample") {
      continue;
    }

    const sample = {
      t: Number(row[columns.t_ms]),
      roll: Number(row[columns.roll]),
      pitch: Number(row[columns.pitch]),
      thr: Number(row[columns.thr]),
      yaw: Number(row[columns.yaw]),
      arm: Number(row[columns.arm]),
    };

    if (Object.values(sample).every(Number.isFinite)) {
      samples.push(sample);
    }
  }

  if (samples.length === 0) {
    throw new Error("CSV has no valid sample rows.");
  }

  return samples.sort((a, b) => a.t - b.t);
}

function sampleAt(timeMs) {
  const samples = state.samples;
  if (samples.length === 0) {
    return null;
  }

  if (timeMs <= samples[0].t) {
    return samples[0];
  }

  const last = samples[samples.length - 1];
  if (timeMs >= last.t) {
    return last;
  }

  let low = 0;
  let high = samples.length - 1;

  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (samples[mid].t < timeMs) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  const before = samples[low - 1];
  const after = samples[low];
  const span = after.t - before.t || 1;
  const ratio = (timeMs - before.t) / span;

  return {
    t: timeMs,
    roll: before.roll + (after.roll - before.roll) * ratio,
    pitch: before.pitch + (after.pitch - before.pitch) * ratio,
    thr: before.thr + (after.thr - before.thr) * ratio,
    yaw: before.yaw + (after.yaw - before.yaw) * ratio,
    arm: ratio < 0.5 ? before.arm : after.arm,
  };
}

function resizeCanvas() {
  const rect = stage.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.round(rect.width * dpr));
  const height = Math.max(1, Math.round(rect.height * dpr));

  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
}

function drawStick(targetCtx, centerX, centerY, size, xValue, yValue, labelX, labelY) {
  const radius = size / 2;
  const knobRadius = Math.max(6, size * 0.075);
  const x = centerX + clamp(xValue / 1000, -1, 1) * radius * 0.76;
  const y = centerY - clamp(yValue / 1000, -1, 1) * radius * 0.76;

  targetCtx.save();
  targetCtx.lineWidth = Math.max(2, size * 0.018);
  targetCtx.strokeStyle = "rgb(255 255 255 / 0.26)";
  targetCtx.fillStyle = "rgb(0 0 0 / 0.38)";
  targetCtx.beginPath();
  targetCtx.roundRect(centerX - radius, centerY - radius, size, size, size * 0.1);
  targetCtx.fill();
  targetCtx.stroke();

  targetCtx.strokeStyle = "rgb(255 255 255 / 0.18)";
  targetCtx.beginPath();
  targetCtx.moveTo(centerX - radius * 0.8, centerY);
  targetCtx.lineTo(centerX + radius * 0.8, centerY);
  targetCtx.moveTo(centerX, centerY - radius * 0.8);
  targetCtx.lineTo(centerX, centerY + radius * 0.8);
  targetCtx.stroke();

  targetCtx.strokeStyle = "rgb(126 231 135 / 0.85)";
  targetCtx.beginPath();
  targetCtx.moveTo(centerX, centerY);
  targetCtx.lineTo(x, y);
  targetCtx.stroke();

  targetCtx.fillStyle = "#7ee787";
  targetCtx.beginPath();
  targetCtx.arc(x, y, knobRadius, 0, Math.PI * 2);
  targetCtx.fill();

  targetCtx.fillStyle = "rgb(243 241 232 / 0.86)";
  targetCtx.font = `${Math.max(10, size * 0.075)}px ui-sans-serif, system-ui, sans-serif`;
  targetCtx.textAlign = "center";
  targetCtx.fillText(labelX, centerX, centerY + radius + size * 0.16);
  targetCtx.fillText(labelY, centerX, centerY - radius - size * 0.08);
  targetCtx.restore();
}

function paintOverlay(targetCtx, width, height, sample, csvTimeMs) {
  if (!sample) {
    return;
  }

  const base = Math.min(width, height);
  const scale = state.scale;
  const stickSize = clamp(base * 0.18 * scale, 92, 190 * scale);
  const gap = stickSize * 0.24;
  const padding = Math.max(22, base * 0.04);
  const overlayWidth = stickSize * 2 + gap;
  const overlayHeight = stickSize + 62 * scale;

  const right = state.position.endsWith("right");
  const top = state.position.startsWith("top");
  const originX = right ? width - padding - overlayWidth : padding;
  const originY = top ? padding : height - padding - overlayHeight;

  targetCtx.save();
  targetCtx.globalAlpha = state.opacity;

  const leftX = originX + stickSize / 2;
  const rightX = originX + stickSize + gap + stickSize / 2;
  const centerY = originY + stickSize / 2 + 22 * scale;

  drawStick(targetCtx, leftX, centerY, stickSize, sample.yaw, sample.thr, "YAW", "THR");
  drawStick(targetCtx, rightX, centerY, stickSize, sample.roll, sample.pitch, "ROLL", "PITCH");

  targetCtx.font = `${Math.max(12, stickSize * 0.085)}px ui-sans-serif, system-ui, sans-serif`;
  targetCtx.textAlign = "left";
  targetCtx.textBaseline = "middle";
  const armText = sample.arm ? "ARMED" : "DISARMED";
  const armColor = sample.arm ? "#7ee787" : "#ff7b72";
  const chipWidth = targetCtx.measureText(armText).width + 24 * scale;
  const chipHeight = 26 * scale;
  const chipX = originX;
  const chipY = originY;

  targetCtx.fillStyle = "rgb(0 0 0 / 0.52)";
  targetCtx.beginPath();
  targetCtx.roundRect(chipX, chipY, chipWidth, chipHeight, 6 * scale);
  targetCtx.fill();
  targetCtx.fillStyle = armColor;
  targetCtx.fillText(armText, chipX + 12 * scale, chipY + chipHeight / 2);

  targetCtx.textAlign = "right";
  targetCtx.fillStyle = "rgb(243 241 232 / 0.82)";
  targetCtx.fillText(`${Math.max(0, csvTimeMs / 1000).toFixed(2)}s`, originX + overlayWidth, chipY + chipHeight / 2);
  targetCtx.restore();
}

function drawOverlay(sample, csvTimeMs) {
  resizeCanvas();
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  paintOverlay(ctx, canvas.width, canvas.height, sample, csvTimeMs);
}

function updateReadout(sample, csvTimeMs) {
  videoTime.textContent = `${video.currentTime.toFixed(2)}s`;
  csvTime.textContent = formatMs(csvTimeMs);
  armState.textContent = sample ? (sample.arm ? "ARMED" : "DISARMED") : "-";
}

function render() {
  const csvTimeMs = video.currentTime * 1000 + state.offsetMs;
  const sample = sampleAt(csvTimeMs);
  drawOverlay(sample, csvTimeMs);
  updateReadout(sample, csvTimeMs);
  requestAnimationFrame(render);
}

function updateControls() {
  offsetValue.textContent = formatMs(state.offsetMs);
  scaleValue.textContent = `${Math.round(state.scale * 100)}%`;
  opacityValue.textContent = `${Math.round(state.opacity * 100)}%`;
}

videoInput.addEventListener("change", () => {
  const file = videoInput.files[0];
  if (!file) {
    return;
  }

  if (state.videoUrl) {
    URL.revokeObjectURL(state.videoUrl);
  }

  state.videoUrl = URL.createObjectURL(file);
  video.src = state.videoUrl;
  video.load();
  emptyState.hidden = true;
  downloadLink.hidden = true;
  setMessage(`Video selected: ${file.name}`);
});

csvInput.addEventListener("change", async () => {
  const file = csvInput.files[0];
  if (!file) {
    return;
  }

  try {
    const text = await file.text();
    state.samples = parseStickCsv(text);
    const last = state.samples[state.samples.length - 1];
    sampleCount.textContent = String(state.samples.length);
    logLength.textContent = `${(last.t / 1000).toFixed(1)}s`;
    downloadLink.hidden = true;
    setMessage(`CSV loaded: ${file.name}`);
  } catch (error) {
    state.samples = [];
    sampleCount.textContent = "0";
    logLength.textContent = "0.0s";
    setMessage(error.message, true);
  }
});

function bestMimeType() {
  const types = [
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm",
  ];

  return types.find((type) => MediaRecorder.isTypeSupported(type)) || "";
}

function waitForEvent(target, eventName) {
  return new Promise((resolve) => {
    target.addEventListener(eventName, resolve, { once: true });
  });
}

async function seekVideo(seconds) {
  if (Math.abs(video.currentTime - seconds) < 0.02) {
    return;
  }

  video.currentTime = seconds;
  await waitForEvent(video, "seeked");
}

function drawRenderedFrame(targetCtx, targetCanvas) {
  targetCtx.fillStyle = "#050605";
  targetCtx.fillRect(0, 0, targetCanvas.width, targetCanvas.height);
  targetCtx.drawImage(video, 0, 0, targetCanvas.width, targetCanvas.height);

  const csvTimeMs = video.currentTime * 1000 + state.offsetMs;
  paintOverlay(targetCtx, targetCanvas.width, targetCanvas.height, sampleAt(csvTimeMs), csvTimeMs);
}

function captureVideoAudioTracks() {
  if (!video.captureStream) {
    return [];
  }

  return video.captureStream().getAudioTracks();
}

async function exportRenderedVideo() {
  if (!state.videoUrl) {
    setMessage("Select a video first.", true);
    return;
  }

  if (state.samples.length === 0) {
    setMessage("Select a CSV log first.", true);
    return;
  }

  if (!window.MediaRecorder) {
    setMessage("This browser cannot render video with MediaRecorder.", true);
    return;
  }

  const mimeType = bestMimeType();
  if (!mimeType) {
    setMessage("This browser has no supported WebM encoder.", true);
    return;
  }

  if (!Number.isFinite(video.duration) || video.duration <= 0) {
    setMessage("Video metadata is not ready yet.", true);
    return;
  }

  state.exporting = true;
  exportButton.disabled = true;
  downloadLink.hidden = true;
  exportProgress.value = 0;
  setMessage("Rendering video in real time...");

  const previousTime = video.currentTime;
  const wasPaused = video.paused;
  const previousMuted = video.muted;
  const renderCanvas = document.createElement("canvas");
  renderCanvas.width = video.videoWidth || 1280;
  renderCanvas.height = video.videoHeight || 720;
  const renderCtx = renderCanvas.getContext("2d");
  const stream = renderCanvas.captureStream(30);

  for (const track of captureVideoAudioTracks()) {
    stream.addTrack(track);
  }

  const chunks = [];
  const recorder = new MediaRecorder(stream, { mimeType });
  recorder.addEventListener("dataavailable", (event) => {
    if (event.data.size > 0) {
      chunks.push(event.data);
    }
  });

  const stopped = waitForEvent(recorder, "stop");

  await seekVideo(0);
  video.muted = true;
  recorder.start(1000);

  let frameId = 0;
  let exportError = null;
  const drawLoop = () => {
    if (!state.exporting) {
      return;
    }

    drawRenderedFrame(renderCtx, renderCanvas);
    exportProgress.value = clamp((video.currentTime / video.duration) * 100, 0, 100);

    if (video.ended || video.currentTime >= video.duration) {
      state.exporting = false;
      recorder.stop();
      return;
    }

    frameId = requestAnimationFrame(drawLoop);
  };

  frameId = requestAnimationFrame(drawLoop);

  try {
    await video.play();
    await waitForEvent(video, "ended");
  } catch (error) {
    exportError = error;
    state.exporting = false;
    cancelAnimationFrame(frameId);
    if (recorder.state !== "inactive") {
      recorder.stop();
    }
  }

  await stopped;
  cancelAnimationFrame(frameId);
  video.muted = previousMuted;
  await seekVideo(previousTime);
  if (!wasPaused) {
    await video.play();
  }

  exportButton.disabled = false;

  if (exportError) {
    setMessage(exportError.message, true);
    return;
  }

  if (state.renderUrl) {
    URL.revokeObjectURL(state.renderUrl);
  }

  const blob = new Blob(chunks, { type: mimeType });
  state.renderUrl = URL.createObjectURL(blob);
  downloadLink.href = state.renderUrl;
  downloadLink.download = "stick-overlay.webm";
  downloadLink.hidden = false;
  exportProgress.value = 100;
  setMessage(`Rendered ${(blob.size / 1024 / 1024).toFixed(1)} MB WebM.`);
}

offsetInput.addEventListener("input", () => {
  state.offsetMs = Number(offsetInput.value);
  updateControls();
});

scaleInput.addEventListener("input", () => {
  state.scale = Number(scaleInput.value) / 100;
  updateControls();
});

opacityInput.addEventListener("input", () => {
  state.opacity = Number(opacityInput.value) / 100;
  updateControls();
});

positionInput.addEventListener("change", () => {
  state.position = positionInput.value;
});

document.getElementById("nudgeBack").addEventListener("click", () => {
  state.offsetMs = clamp(state.offsetMs - 100, Number(offsetInput.min), Number(offsetInput.max));
  offsetInput.value = String(state.offsetMs);
  updateControls();
});

document.getElementById("nudgeForward").addEventListener("click", () => {
  state.offsetMs = clamp(state.offsetMs + 100, Number(offsetInput.min), Number(offsetInput.max));
  offsetInput.value = String(state.offsetMs);
  updateControls();
});

document.getElementById("resetOffset").addEventListener("click", () => {
  state.offsetMs = 0;
  offsetInput.value = "0";
  updateControls();
});

exportButton.addEventListener("click", () => {
  exportRenderedVideo().catch((error) => {
    state.exporting = false;
    exportButton.disabled = false;
    setMessage(error.message, true);
  });
});

if ("ResizeObserver" in window) {
  new ResizeObserver(resizeCanvas).observe(stage);
} else {
  window.addEventListener("resize", resizeCanvas);
}

updateControls();
resizeCanvas();
requestAnimationFrame(render);
