#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const audio = requireFromRoot('shell/plugins/panels/audio/Model.js')

assert(audio.isPlaybackStream({ isStream: true, isSink: true }), 'audio detects sink-backed playback streams')
assert(audio.isPlaybackStream({ isStream: true, type: 'Stream/Output/Audio' }), 'audio detects typed playback streams')
assert(!audio.isPlaybackStream({ isStream: false, isSink: true }), 'audio rejects non-stream playback nodes')
assert(audio.isAudioSource({ audio: {} }), 'audio detects nodes with audio as sources')
assert(audio.isAudioSource({ type: 'Audio/Source' }), 'audio detects typed source nodes')

assertEqual(audio.outputVolumeName(0, false), 'Silenced', 'audio labels silent output')
assertEqual(audio.outputVolumeName(0.9, false), 'Party mode', 'audio labels loud output')
assertEqual(audio.outputVolumeName(0.5, true), 'Muted', 'audio labels muted output')

assertDeepEqual(audio.parseSinkAvailability('alsa_output\t1\nhdmi_output\t0\n'), { alsa_output: true, hdmi_output: false }, 'audio parses sink availability')
assertEqual(audio.friendlyDeviceLabel('Built-in Audio Speakers Output'), 'Speakers', 'audio cleans device labels')
assertEqual(
  audio.nodeLabel({ ready: true, properties: { 'node.nick': 'Built-in Audio Microphones Input' }, name: 'alsa_input' }),
  'Microphone',
  'audio chooses friendly node labels'
)
const mixerOutputs = [1, 2, 3].map((n) => ({
  ready: true,
  id: 40 + n,
  description: `Mixer Output ${n}`,
  nickname: 'Mixer',
  properties: { 'node.nick': 'Mixer' },
  name: `alsa_output.mixer.output-${n}`
}))
assertEqual(
  audio.nodeLabel(mixerOutputs[1], mixerOutputs),
  'Mixer Output 2',
  'audio prefers endpoint descriptions over shared device nicknames'
)

const hdmiSink = {
  ready: true,
  id: 51,
  description: 'GA104 High Definition Audio Controller Digital Stereo (HDMI)',
  nickname: 'LG HDR 4K',
  properties: { 'node.nick': 'LG HDR 4K' },
  name: 'alsa_output.pci-0000_01_00.1.hdmi-stereo'
}
const analogSink = {
  ready: true,
  id: 52,
  description: 'Built-in Audio Analog Stereo',
  nickname: 'Built-in Audio Speakers Output',
  properties: { 'node.nick': 'Built-in Audio Speakers Output' },
  name: 'alsa_output.pci-0000_00_1f.3.analog-stereo'
}
assertEqual(
  audio.nodeLabel(hdmiSink, [hdmiSink, analogSink]),
  'LG HDR 4K',
  'audio keeps the display nickname for HDMI sinks'
)
assertEqual(
  audio.nodeLabel(hdmiSink),
  'LG HDR 4K',
  'audio keeps distinctive nicknames when no peers are known'
)
assertEqual(
  audio.nodeLabel(analogSink, [hdmiSink, analogSink]),
  'Speakers',
  'audio cleans unshared nicknames instead of falling back to descriptions'
)
assert(
  audio.nicknameIsShared(mixerOutputs[0], mixerOutputs),
  'audio spots nicknames shared across endpoints'
)
assert(
  !audio.nicknameIsShared(hdmiSink, [hdmiSink, analogSink]),
  'audio does not treat a node as sharing its own nickname'
)

const headphones = { ready: true, name: 'bluez_output.airpods', properties: { 'device.product.name': 'AirPods Headphones' } }
assert(audio.isHeadphones(headphones), 'audio detects headphone devices')
assertEqual(audio.sinkGlyph(headphones), '󰋋', 'audio uses headphone sink glyph')
assert(audio.sourceGlyph({ ready: true, properties: { 'device.icon-name': 'camera-webcam' } }).length > 0, 'audio maps webcam source glyph')

assertEqual(audio.friendlyStreamLabel('spotify'), 'Spotify', 'audio normalizes known stream labels')
assert(audio.streamRepresentsMprisPlayer('Chromium', 'Chromium Browser'), 'audio matches related stream and MPRIS labels')

const players = [
  { identity: 'Spotify', canPlay: true, isPlaying: true, dbusName: 'org.mpris.MediaPlayer2.spotify' },
  { identity: 'Chromium', canPlay: true, isPlaying: false, dbusName: 'org.mpris.MediaPlayer2.chromium' }
]
const streams = [
  { ready: true, properties: { 'application.name': 'Chromium' } },
  { ready: true, properties: { 'application.name': 'audio-src' } }
]

assertEqual(audio.matchingMprisStreamLabel('Chromium', players), 'Chromium', 'audio finds matching MPRIS labels')
assertEqual(audio.unmatchedMprisStreamLabel('audio-src', players, streams), 'Spotify', 'audio uses unmatched MPRIS player for generic streams')
assertEqual(audio.streamLabel(streams[1], players, streams), 'Spotify', 'audio labels generic streams from MPRIS')
assert(audio.streamRepresentsPlayer(streams[1], players[0], players, streams), 'audio links generic streams to active player')
JS
