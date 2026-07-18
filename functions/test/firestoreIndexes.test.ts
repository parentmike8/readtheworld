import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

type FieldIndex = {
  queryScope?: string;
  order?: string;
  arrayConfig?: string;
};

type FieldOverride = {
  collectionGroup?: string;
  fieldPath?: string;
  indexes?: FieldIndex[];
};

const repositoryRoot = path.resolve(__dirname, "../..");
const indexConfig = JSON.parse(readFileSync(
  path.join(repositoryRoot, "firebase/firestore.indexes.json"),
  "utf8",
)) as { fieldOverrides?: FieldOverride[] };
const packageConfig = JSON.parse(readFileSync(
  path.join(repositoryRoot, "package.json"),
  "utf8",
)) as { scripts?: Record<string, string> };

function configuredModes(override: FieldOverride): Set<string> {
  return new Set((override.indexes ?? []).map((index) =>
    `${index.queryScope}:${index.order ?? index.arrayConfig ?? ""}`,
  ));
}

describe("Firestore field overrides", () => {
  it("retains collection defaults when enabling collection-group indexes", () => {
    const collectionGroupOverrides = (indexConfig.fieldOverrides ?? [])
      .filter((override) => (override.indexes ?? [])
        .some((index) => index.queryScope === "COLLECTION_GROUP"));

    expect(collectionGroupOverrides.length).toBeGreaterThan(0);
    for (const override of collectionGroupOverrides) {
      const modes = configuredModes(override);
      expect(modes, `${override.collectionGroup}.${override.fieldPath}`)
        .toContain("COLLECTION:ASCENDING");
      expect(modes, `${override.collectionGroup}.${override.fieldPath}`)
        .toContain("COLLECTION:DESCENDING");
    }
  });

  it("keeps notification token broadcasts indexed in collection-group scope", () => {
    const override = (indexConfig.fieldOverrides ?? []).find((item) =>
      item.collectionGroup === "notificationTokens" && item.fieldPath === "enabled",
    );
    expect(override).toBeDefined();
    expect(configuredModes(override ?? {})).toContain("COLLECTION_GROUP:ASCENDING");
  });

  it("deploys Firestore indexes before Functions", () => {
    expect(packageConfig.scripts?.["deploy:indexes"])
      .toContain("--only firestore:indexes");
    expect(packageConfig.scripts?.["deploy:functions"])
      .toMatch(/^npm run deploy:indexes && /);
  });
});
