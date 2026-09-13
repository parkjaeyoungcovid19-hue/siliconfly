"""bridge.py - TCP server (Swift is the client). Modes:
  python bridge.py --mock    kinematic body, no MuJoCo, for loop tests
  python bridge.py --flygym  real FlyGym 2.x NeuroMechFly body
"""
from __future__ import annotations
import argparse
import socket
import sys
import threading
import time
import os
from collections import deque
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from protocol import (
    decode_line, encode, BrainPacket, BodyPacket, LabCommand, LabStatePacket, LabEventPacket,
    LabCommandQueue,
)
from neural_decoder import decode, LocomotorCommand

HOST = "127.0.0.1"
PORT = 17841

class Bridge:
    def __init__(self, mode="mock", config=None, show_viewer=False):
        self.mode = mode
        if mode == "flygym":
            from fly_body import RealFlyBody
            self.body = RealFlyBody(config=config, show_viewer=show_viewer)
        else:
            from fly_body import MockBody
            self.body = MockBody()
        self.latest_brain = BrainPacket()
        self.lock = threading.Lock()
        self.lab_commands = LabCommandQueue()
        self.pending_lab_responses = deque(maxlen=128)
        self.brain_count = 0
        self.body_count = 0
        self.lab_count = 0
        self.lab_applied = 0
        self.lab_rejected = 0
        self.malformed = 0
        self.running = False
        self.last_cmd = LocomotorCommand()
        self.last_brain_mono = time.monotonic()
        self.last_behavior_log = 0.0
        self.last_lab_action = ""
        self.smoke_log = os.environ.get("SILICONFLY_SMOKE_LOG") == "1"

    def handle_line(self, line: bytes):
        pkt = decode_line(line)
        if pkt is None:
            self.malformed += 1
            return
        if isinstance(pkt, BrainPacket):
            with self.lock:
                self.latest_brain = pkt
                self.brain_count += 1
                self.last_cmd = decode(pkt)
                self.last_brain_mono = time.monotonic()
        elif isinstance(pkt, LabCommand):
            self.lab_count += 1
            if not self.lab_commands.push(pkt):
                self.lab_rejected += 1
                self._queue_lab_response(LabStatePacket(
                    ack=pkt.seq, ok=False, error="lab command queue full",
                    state={"last_action": pkt.op}))

    def _queue_lab_response(self, packet):
        with self.lock:
            self.pending_lab_responses.append(packet)

    def _drain_lab_responses(self):
        with self.lock:
            out = list(self.pending_lab_responses)
            self.pending_lab_responses.clear()
        return out

    def _brain_snapshot(self, now_mono=None):
        """Return the current decoded command, tempo and monotonic packet age."""
        if now_mono is None:
            now_mono = time.monotonic()
        with self.lock:
            cmd = self.last_cmd
            tempo = self.latest_brain.tempo
            age_s = max(0.0, float(now_mono) - self.last_brain_mono)
        stale = age_s > 1.0
        if stale:
            return LocomotorCommand(), 1.0, age_s, True
        return cmd, tempo, age_s, False

    def _lab_state(self, *, ack=None, ok=True, error=None, last_action=None):
        state_fn = getattr(self.body, "lab_state", None)
        state = state_fn() if state_fn is not None else {}
        state = dict(state or {})
        state["queue"] = self.lab_commands.stats()
        state["commands_received"] = self.lab_count
        state["commands_applied"] = self.lab_applied
        state["commands_rejected"] = self.lab_rejected
        _, _, brain_age_s, brain_stale = self._brain_snapshot()
        state["bridge_timing"] = {
            "brain_age_ms": brain_age_s * 1000.0,
            "brain_stale": brain_stale,
        }
        if last_action is not None:
            state["last_action"] = last_action
        elif self.last_lab_action:
            state["last_action"] = self.last_lab_action
        return LabStatePacket(ack=ack, ok=ok, error=error, state=state)

    def _apply_lab_commands(self):
        apply_fn = getattr(self.body, "apply_lab_command", None)
        if apply_fn is None:
            return
        # Limit discrete work per body tick; continuous slots are always drained
        # as latest state. Remaining discrete FIFO entries stay bounded in queue.
        for command in self.lab_commands.drain(max_discrete=32):
            try:
                apply_fn(command)
                self.lab_applied += 1
                self.last_lab_action = command.op
                self._queue_lab_response(self._lab_state(
                    ack=command.seq, ok=True, last_action=command.op))
            except Exception as exc:
                self.lab_rejected += 1
                self.last_lab_action = command.op
                self._queue_lab_response(self._lab_state(
                    ack=command.seq, ok=False, error=str(exc)[:512],
                    last_action=command.op))

    def _collect_lab_events(self):
        drain_fn = getattr(self.body, "drain_lab_events", None)
        if drain_fn is None:
            return
        for item in drain_fn():
            if not isinstance(item, dict):
                continue
            data = dict(item)
            event = str(data.pop("event", "lab_event"))[:64]
            self._queue_lab_response(LabEventPacket(event=event, data=data))

    def serve_once(self, conn):
        # Receive on its own thread: a slow MuJoCo/viewer tick must never stop
        # the 50-100 Hz BrainSignals stream from reaching the bounded latest
        # packet slot.
        alive = threading.Event()
        alive.set()
        # Keep receive waits well below the 15 ms feedback period. A 50 ms
        # timeout capped feedback near 40 Hz whenever the client was quiet
        # between packets; 5 ms keeps the loop in the requested 50-100 Hz
        # range without busy-spinning.
        conn.settimeout(0.005)
        def receive():
            buf = b""
            first_brain_at = None
            last_brain_at = None
            while self.running and alive.is_set():
                try:
                    chunk = conn.recv(4096)
                    if chunk == b"":
                        break
                except socket.timeout:
                    continue
                except OSError:
                    break
                buf += chunk
                if len(buf) > 65536:
                    buf = b""
                    self.malformed += 1
                    continue
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        before = self.brain_count
                        self.handle_line(line + b"\n")
                        if self.brain_count != before:
                            last_brain_at = time.monotonic()
                            if first_brain_at is None:
                                first_brain_at = last_brain_at
            if first_brain_at is not None and last_brain_at is not None:
                count = self.brain_count - brain_at_connect
                span = max(1e-6, last_brain_at - first_brain_at)
                self.last_session_brain_hz = max(0.0, count - 1) / span
            alive.clear()

        brain_at_connect = self.brain_count
        body_at_connect = self.body_count
        self.last_session_brain_hz = 0.0
        receiver = threading.Thread(target=receive, daemon=True)
        receiver.start()
        period = 1.0 / 60.0
        # Full LabWorld state is intentionally much heavier than a body packet.
        # Commands already get an immediate state ack, so a low-rate heartbeat
        # is enough for passive UI freshness without stealing closed-loop socket
        # throughput from the 60 Hz body stream.
        lab_state_period = 0.50
        last = time.monotonic()
        next_tick = last
        next_lab_state = last
        smoke_window_start = last
        smoke_body_start = self.body_count
        smoke_brain_start = self.brain_count
        smoke_last_body = None
        smoke_max_gap = 0.0
        smoke_sim_s = 0.0
        smoke_wall_s = 0.0
        while self.running and alive.is_set():
            now_mono = time.monotonic()
            if now_mono < next_tick:
                time.sleep(min(0.002, next_tick - now_mono))
                continue
            dt = min(0.05, max(0.005, now_mono - last))
            last = now_mono
            next_tick = max(next_tick + period, now_mono)
            cmd, tempo, _, brain_stale = self._brain_snapshot(now_mono)
            if not brain_stale and (cmd.groom_state > 0.01 or cmd.wing_state > 0.01) and now_mono - self.last_behavior_log >= 2.0:
                # The selected locomotion controller has no grooming/flight
                # action. Expose these neural readouts honestly without faking
                # unsupported joint behavior.
                print(f"bridge: unsupported-state display groom={cmd.groom_state:.2f} "
                      f"wing={cmd.wing_state:.2f}", flush=True)
                self.last_behavior_log = now_mono
            try:
                # Only this serve loop advances MuJoCo, so all LabWorld model/data
                # mutations happen here on the simulation-owner thread.
                self._apply_lab_commands()
                obs = self.body.step(cmd, dt, tempo=tempo)
                self._collect_lab_events()
            except Exception as e:
                print(f"bridge: body step failed: {e}", flush=True)
                break
            try:
                conn.sendall(encode(obs))
                self.body_count += 1
                sent_at = time.monotonic()
                if smoke_last_body is not None:
                    smoke_max_gap = max(smoke_max_gap, sent_at - smoke_last_body)
                smoke_last_body = sent_at
                smoke_sim_s += float(getattr(obs, "sim_dt", 0.0))
                smoke_wall_s += float(getattr(obs, "wall_dt", 0.0))
                for response in self._drain_lab_responses():
                    conn.sendall(encode(response))
                if now_mono >= next_lab_state:
                    conn.sendall(encode(self._lab_state()))
                    next_lab_state = now_mono + lab_state_period
            except OSError:
                break
            if self.smoke_log and now_mono - smoke_window_start >= 5.0:
                span = max(1e-6, now_mono - smoke_window_start)
                body_hz = (self.body_count - smoke_body_start) / span
                brain_hz = (self.brain_count - smoke_brain_start) / span
                ratio = smoke_sim_s / smoke_wall_s if smoke_wall_s > 0.0 else 0.0
                print(
                    f"bridge-smoke: body_hz={body_hz:.1f} brain_hz={brain_hz:.1f} "
                    f"max_body_gap_ms={smoke_max_gap * 1000.0:.1f} sim_wall={ratio:.3f}",
                    flush=True,
                )
                smoke_window_start = now_mono
                smoke_body_start = self.body_count
                smoke_brain_start = self.brain_count
                smoke_max_gap = 0.0
                smoke_sim_s = 0.0
                smoke_wall_s = 0.0
        alive.clear()
        try:
            conn.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            conn.close()
        except OSError:
            pass
        receiver.join(timeout=0.1)
        # Connection-local counts make arrival/drop behavior visible.
        print(f"bridge: session brain={self.brain_count-brain_at_connect} "
              f"body={self.body_count-body_at_connect} "
              f"lab={self.lab_count} applied={self.lab_applied} rejected={self.lab_rejected} "
              f"brain_hz={self.last_session_brain_hz:.1f}", flush=True)

    def serve(self):
        self.running = True
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(1)
        srv.settimeout(0.2)
        print(f"bridge listening on {HOST}:{PORT} mode={self.mode}", flush=True)
        try:
            while self.running:
                try:
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                print("bridge: client connected", flush=True)
                self.serve_once(conn)
                print("bridge: client disconnected", flush=True)
        except KeyboardInterrupt:
            print("bridge: stopping", flush=True)
        finally:
            srv.close()
            close = getattr(self.body, "close", None)
            if close is not None:
                close()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--flygym", action="store_true")
    ap.add_argument("--flygym-headless", action="store_true")
    args = ap.parse_args()
    if args.flygym or args.flygym_headless:
        from environment import ArenaConfig
        Bridge(mode="flygym", config=ArenaConfig(), show_viewer=args.flygym).serve()
    else:
        Bridge(mode="mock").serve()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        # mjpython delivers Ctrl-C from its Cocoa trampoline differently from
        # ordinary CPython; keep interactive shutdown clean in either case.
        pass
