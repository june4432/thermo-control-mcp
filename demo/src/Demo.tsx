import React from "react";
import {
  AbsoluteFill,
  Sequence,
  interpolate,
  interpolateColors,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export const DEMO_WIDTH = 800;
export const DEMO_HEIGHT = 450;
export const DEMO_FPS = 30;
export const DEMO_DURATION = 750;

const MONO = "'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace";

const C = {
  bg: "#0a0e14",
  panel: "#10151f",
  border: "rgba(255,255,255,0.09)",
  text: "#c9d4e3",
  dim: "#5c6a7e",
  red: "#ff5560",
  amber: "#ffb454",
  mint: "#3fe0a0",
  cyan: "#56c8ff",
  violet: "#b78cff",
};

// ---------------------------------------------------------------- utilities

const Typed: React.FC<{
  text: string;
  start: number;
  cps?: number; // characters per frame
  color?: string;
  size?: number;
  caret?: boolean;
}> = ({ text, start, cps = 1.2, color = C.text, size = 17, caret = true }) => {
  const frame = useCurrentFrame();
  const chars = Math.max(0, Math.floor((frame - start) * cps));
  if (frame < start) return null;
  const done = chars >= text.length;
  const blink = Math.floor(frame / 12) % 2 === 0;
  return (
    <div style={{ fontFamily: MONO, fontSize: size, color, whiteSpace: "pre" }}>
      {text.slice(0, chars)}
      {caret && (!done || blink) ? (
        <span style={{ color: C.cyan }}>▌</span>
      ) : null}
    </div>
  );
};

const FadeIn: React.FC<{
  start: number;
  children: React.ReactNode;
  rise?: number;
}> = ({ start, children, rise = 10 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: frame - start, fps, config: { damping: 200 } });
  if (frame < start) return null;
  return (
    <div style={{ opacity: s, transform: `translateY(${(1 - s) * rise}px)` }}>
      {children}
    </div>
  );
};

const ToolChip: React.FC<{ label: string; start: number }> = ({
  label,
  start,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: frame - start, fps, config: { damping: 14 } });
  if (frame < start) return null;
  const spinnerChars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴"];
  const settled = frame - start > 24;
  const spin = spinnerChars[Math.floor((frame - start) / 4) % 6];
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        transform: `scale(${0.9 + s * 0.1})`,
        opacity: s,
        background: "rgba(183,140,255,0.10)",
        border: `1px solid rgba(183,140,255,0.35)`,
        borderRadius: 8,
        padding: "6px 12px",
        fontFamily: MONO,
        fontSize: 15,
        color: C.violet,
      }}
    >
      <span>{settled ? "✓" : spin}</span>
      <span>{label}</span>
    </div>
  );
};

// A scene wrapper that fades in at its start and out at its end.
const Scene: React.FC<{
  duration: number;
  children: React.ReactNode;
}> = ({ duration, children }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(
    frame,
    [0, 12, duration - 12, duration],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

// ------------------------------------------------------------------- frame

const Ambient: React.FC = () => {
  const frame = useCurrentFrame();
  // The room "cools down" over the video: red glow → teal glow.
  const glow = interpolateColors(
    frame,
    [0, 300, 470, 620],
    ["#3d0f14", "#3d0f14", "#0c3330", "#0c2a33"]
  );
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(1000px 560px at 50% -10%, ${glow} 0%, ${C.bg} 62%)`,
      }}
    />
  );
};

const Terminal: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ padding: 26 }}>
    <div
      style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        background: C.panel,
        borderRadius: 14,
        border: `1px solid ${C.border}`,
        boxShadow: "0 24px 70px rgba(0,0,0,0.55)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "12px 16px",
          borderBottom: `1px solid ${C.border}`,
        }}
      >
        {[C.red, C.amber, C.mint].map((color) => (
          <div
            key={color}
            style={{
              width: 11,
              height: 11,
              borderRadius: 6,
              background: color,
              opacity: 0.9,
            }}
          />
        ))}
        <div
          style={{
            flex: 1,
            textAlign: "center",
            fontFamily: MONO,
            fontSize: 13,
            color: C.dim,
          }}
        >
          claude code — thermo-control-mcp
        </div>
      </div>
      <div style={{ flex: 1, padding: "20px 28px", position: "relative" }}>
        {children}
      </div>
    </div>
  </AbsoluteFill>
);

// ------------------------------------------------------------------ scenes

const SceneHot: React.FC = () => {
  const frame = useCurrentFrame();
  const pulse = 1 + Math.sin(frame / 7) * 0.02;
  return (
    <Scene duration={115}>
      <AbsoluteFill
        style={{ alignItems: "center", justifyContent: "center", gap: 10 }}
      >
        <div
          style={{
            fontFamily: MONO,
            fontWeight: 700,
            fontSize: 104,
            color: C.red,
            transform: `scale(${pulse})`,
            textShadow: "0 0 60px rgba(255,85,96,0.55)",
          }}
        >
          91.1°C
        </div>
        <div style={{ fontFamily: MONO, fontSize: 16, color: C.dim }}>
          CPU die temperature · fans idling at 2,300 rpm
        </div>
        <div style={{ height: 14 }} />
        <Typed
          start={55}
          text="macOS battery menu says: “Terminal is using significant energy” …thanks."
          color={C.dim}
          size={15}
        />
      </AbsoluteFill>
    </Scene>
  );
};

const Row: React.FC<{
  start: number;
  cells: [string, string, string, string];
  highlight?: boolean;
  struck?: boolean;
}> = ({ start, cells, highlight, struck }) => {
  const widths = [90, 90, 100, 330];
  return (
    <FadeIn start={start}>
      <div
        style={{
          display: "flex",
          fontFamily: MONO,
          fontSize: 15.5,
          lineHeight: "27px",
          color: highlight ? "#ffd7da" : C.text,
          background: highlight ? "rgba(255,85,96,0.14)" : "transparent",
          borderLeft: highlight
            ? `3px solid ${C.red}`
            : "3px solid transparent",
          paddingLeft: 10,
          textDecoration: struck ? "line-through" : "none",
          opacity: struck ? 0.4 : 1,
        }}
      >
        {cells.map((cell, i) => (
          <div key={i} style={{ width: widths[i], whiteSpace: "pre" }}>
            {cell}
          </div>
        ))}
        {highlight && !struck ? (
          <div
            style={{
              alignSelf: "center",
              fontSize: 11,
              color: C.red,
              border: `1px solid ${C.red}`,
              borderRadius: 4,
              padding: "0 6px",
              marginLeft: 6,
              lineHeight: "16px",
            }}
          >
            RUNAWAY
          </div>
        ) : null}
      </div>
    </FadeIn>
  );
};

const SceneDiagnose: React.FC = () => {
  return (
    <Scene duration={190}>
      <Terminal>
        <Typed start={6} text="> claude, why is my mac running hot?" color={C.cyan} />
        <div style={{ height: 16 }} />
        <ToolChip label="get_heat_sources" start={44} />
        <div style={{ height: 16 }} />
        <Row
          start={74}
          cells={["PID", "%CPU", "TIME", "COMMAND"]}
        />
        <div style={{ opacity: 0.35 }}>
          <div style={{ height: 1, background: C.border, margin: "4px 0" }} />
        </div>
        <Row
          start={84}
          cells={["72194", "398%", "2h 02m", "java — Eclipse JDT LS (serena)"]}
          highlight
        />
        <Row start={96} cells={["396", "40%", "71h", "WindowServer"]} />
        <Row start={104} cells={["62950", "11%", "3h", "Claude Helper (GPU)"]} />
        <div style={{ height: 18 }} />
        <Typed
          start={120}
          text="→ one language server has been burning 4 CPU cores for 2 hours."
          color={C.amber}
          size={16}
        />
      </Terminal>
    </Scene>
  );
};

const Fan: React.FC<{ rpmStart: number; label: string }> = ({
  rpmStart,
  label,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ramp = spring({
    frame: frame - rpmStart,
    fps,
    config: { damping: 30, mass: 1.4 },
    durationInFrames: 70,
  });
  const rpm = 2317 + (6173 - 2317) * Math.max(0, ramp);
  // Rotation speed grows with rpm; integrating a linear ramp ≈ quadratic angle.
  const angle = frame * 4 + Math.max(0, frame - rpmStart) ** 2 * 0.09;
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
      <svg width={110} height={110} viewBox="-55 -55 110 110">
        <circle r={52} fill="none" stroke={C.border} strokeWidth={2} />
        <g transform={`rotate(${angle % 360})`}>
          {[0, 60, 120, 180, 240, 300].map((blade) => (
            <path
              key={blade}
              d="M 0 -6 C 16 -14, 34 -30, 22 -44 C 12 -36, 4 -22, 0 -6 Z"
              fill={C.cyan}
              opacity={0.85}
              transform={`rotate(${blade})`}
            />
          ))}
          <circle r={7} fill={C.panel} stroke={C.cyan} strokeWidth={2} />
        </g>
      </svg>
      <div style={{ fontFamily: MONO, fontSize: 20, color: C.cyan, fontWeight: 700 }}>
        {Math.round(rpm).toLocaleString()} rpm
      </div>
      <div style={{ fontFamily: MONO, fontSize: 12, color: C.dim }}>{label}</div>
    </div>
  );
};

const SceneAct: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <Scene duration={165}>
      <Terminal>
        <Typed start={4} text="> kill it, and keep me cool while I rebuild" color={C.cyan} />
        <div style={{ height: 12 }} />
        <FadeIn start={34}>
          <div style={{ fontFamily: MONO, fontSize: 15.5, color: C.text }}>
            $ kill 72194{" "}
            <span style={{ color: C.mint }}>{frame > 46 ? " ✓ runaway terminated" : ""}</span>
          </div>
        </FadeIn>
        <div style={{ height: 14 }} />
        <ToolChip label="boost_fans · ttl 600s · dead-man armed" start={58} />
        <div style={{ height: 8 }} />
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            gap: 110,
            marginTop: 6,
          }}
        >
          <Fan rpmStart={70} label="fan 0" />
          <Fan rpmStart={74} label="fan 1" />
        </div>
      </Terminal>
    </Scene>
  );
};

const Spark: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const progress = interpolate(frame, [start, start + 110], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const path = "M 0 8 C 60 6, 110 10, 170 26 C 230 44, 280 66, 360 74";
  const length = 400;
  return (
    <svg width={370} height={86} style={{ overflow: "visible" }}>
      <path
        d={path}
        fill="none"
        stroke="url(#coolGradient)"
        strokeWidth={3.5}
        strokeLinecap="round"
        strokeDasharray={length}
        strokeDashoffset={length * (1 - progress)}
      />
      <defs>
        <linearGradient id="coolGradient" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={C.red} />
          <stop offset="55%" stopColor={C.amber} />
          <stop offset="100%" stopColor={C.mint} />
        </linearGradient>
      </defs>
    </svg>
  );
};

const SceneCool: React.FC = () => {
  const frame = useCurrentFrame();
  const temp = interpolate(frame, [10, 130], [91.1, 65.3], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: (t) => 1 - Math.pow(1 - t, 3),
  });
  const color = interpolateColors(temp, [65.3, 78, 91.1], [C.mint, C.amber, C.red]);
  return (
    <Scene duration={165}>
      <Terminal>
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 6 }}>
          <div
            style={{
              fontFamily: MONO,
              fontWeight: 700,
              fontSize: 88,
              color,
              textShadow: `0 0 46px ${color}55`,
            }}
          >
            {temp.toFixed(1)}°C
          </div>
          <Spark start={10} />
          <div style={{ height: 4 }} />
          <div style={{ display: "flex", gap: 34, fontFamily: MONO, fontSize: 15, color: C.dim }}>
            <span>fans 6,170 rpm</span>
            <span>
              power 27 W → <span style={{ color: C.mint }}>10.5 W</span>
            </span>
          </div>
          <FadeIn start={120}>
            <div style={{ fontFamily: MONO, fontSize: 17, color: C.mint }}>
              −26°C in about a minute
            </div>
          </FadeIn>
        </AbsoluteFill>
      </Terminal>
    </Scene>
  );
};

const SceneOutro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const logo = spring({ frame: frame - 52, fps, config: { damping: 16 } });
  return (
    <Scene duration={115}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 12 }}>
        <ToolChip label="set_fan_auto — control returned to macOS" start={6} />
        <div style={{ height: 8 }} />
        <div
          style={{
            transform: `scale(${0.92 + logo * 0.08})`,
            opacity: logo,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 10,
          }}
        >
          <div
            style={{
              fontFamily: MONO,
              fontWeight: 700,
              fontSize: 44,
              background: `linear-gradient(90deg, ${C.cyan}, ${C.mint})`,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
            }}
          >
            thermo-control-mcp
          </div>
          <div style={{ fontFamily: MONO, fontSize: 17, color: C.text }}>
            your agent keeps your Mac cool
          </div>
          <div style={{ fontFamily: MONO, fontSize: 13, color: C.dim }}>
            root daemon · TTL dead-man switch · 102°C failsafe · RPM clamps
          </div>
          <div style={{ fontFamily: MONO, fontSize: 14, color: C.cyan, marginTop: 6 }}>
            github.com/june4432/thermo-control-mcp
          </div>
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

// -------------------------------------------------------------------- main

export const Demo: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <Ambient />
      <Sequence durationInFrames={115}>
        <SceneHot />
      </Sequence>
      <Sequence from={115} durationInFrames={190}>
        <SceneDiagnose />
      </Sequence>
      <Sequence from={305} durationInFrames={165}>
        <SceneAct />
      </Sequence>
      <Sequence from={470} durationInFrames={165}>
        <SceneCool />
      </Sequence>
      <Sequence from={635} durationInFrames={115}>
        <SceneOutro />
      </Sequence>
    </AbsoluteFill>
  );
};
