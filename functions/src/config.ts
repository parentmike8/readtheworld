export type AdminFeatureFlagKey =
  | "feature_party_mode"
  | "feature_friends"
  | "feature_friends_leaderboard"
  | "feature_result_sharing"
  | "feature_onboarding_demographics";

export type AdminFeatureFlagDefinition = {
  key: AdminFeatureFlagKey;
  label: string;
  description: string;
  defaultValue: boolean;
};

export const ADMIN_FEATURE_FLAGS: AdminFeatureFlagDefinition[] = [
  {
    key: "feature_party_mode",
    label: "Party mode",
    description: "Group play with past questions on a shared screen",
    defaultValue: true,
  },
  {
    key: "feature_friends",
    label: "Friends & social",
    description: "Add friends, compare reads, share results",
    defaultValue: true,
  },
  {
    key: "feature_friends_leaderboard",
    label: "Friends leaderboard",
    description: "Rank friends by Read Score",
    defaultValue: true,
  },
  {
    key: "feature_result_sharing",
    label: "Shareable result cards",
    description: "Let readers share their daily read through rtw.codes",
    defaultValue: true,
  },
  {
    key: "feature_onboarding_demographics",
    label: "Onboarding demographics",
    description: "Collect optional birthdate, gender, and country profile fields",
    defaultValue: true,
  },
];

export function adminFeatureFlagDefinition(
  key: unknown,
): AdminFeatureFlagDefinition | null {
  if (typeof key !== "string") return null;
  return ADMIN_FEATURE_FLAGS.find((flag) => flag.key === key) ?? null;
}

export function remoteConfigBooleanValue(
  value: unknown,
  fallback: boolean,
): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return fallback;
  const normalized = value.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  return fallback;
}

export function remoteConfigParameterBooleanValue(
  parameter: unknown,
  fallback: boolean,
): boolean {
  if (parameter == null || typeof parameter !== "object") return fallback;
  const defaultValue = (parameter as { defaultValue?: unknown }).defaultValue;
  if (defaultValue == null || typeof defaultValue !== "object") return fallback;
  return remoteConfigBooleanValue(
    (defaultValue as { value?: unknown }).value,
    fallback,
  );
}
