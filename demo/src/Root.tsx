import { Composition } from "remotion";
import { Demo, DEMO_DURATION, DEMO_FPS, DEMO_HEIGHT, DEMO_WIDTH } from "./Demo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="Demo"
      component={Demo}
      durationInFrames={DEMO_DURATION}
      fps={DEMO_FPS}
      width={DEMO_WIDTH}
      height={DEMO_HEIGHT}
    />
  );
};
