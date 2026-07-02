import { describe, expect, it } from "vitest";
import {
  ADMIN_FEATURE_FLAGS,
  adminFeatureFlagDefinition,
  remoteConfigBooleanValue,
  remoteConfigParameterBooleanValue,
} from "../src/config";

describe("Admin app config", () => {
  it("keeps feature flag keys allowlisted", () => {
    expect(ADMIN_FEATURE_FLAGS.map((flag) => flag.key)).toEqual([
      "feature_party_mode",
      "feature_friends",
      "feature_friends_leaderboard",
      "feature_result_sharing",
      "feature_onboarding_demographics",
      "feature_world_room_unlocked",
    ]);
    expect(adminFeatureFlagDefinition("feature_party_mode")?.label).toBe("Party mode");
    expect(adminFeatureFlagDefinition("feature_unknown")).toBeNull();
  });

  it("parses remote config boolean values with fallback", () => {
    expect(remoteConfigBooleanValue("true", false)).toBe(true);
    expect(remoteConfigBooleanValue("false", true)).toBe(false);
    expect(remoteConfigBooleanValue(true, false)).toBe(true);
    expect(remoteConfigBooleanValue("not-a-bool", true)).toBe(true);
    expect(remoteConfigBooleanValue(undefined, false)).toBe(false);
  });

  it("reads boolean defaults from remote config template parameters", () => {
    expect(remoteConfigParameterBooleanValue({
      defaultValue: { value: "true" },
    }, false)).toBe(true);
    expect(remoteConfigParameterBooleanValue({
      defaultValue: { value: "false" },
    }, true)).toBe(false);
    expect(remoteConfigParameterBooleanValue({
      defaultValue: { value: "invalid" },
    }, true)).toBe(true);
    expect(remoteConfigParameterBooleanValue(undefined, false)).toBe(false);
  });
});
