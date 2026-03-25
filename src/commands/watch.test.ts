import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { injectAutoRefresh, renderHtml } from "./watch";

const FIXTURE = join(import.meta.dir, "../fixtures/capture.json");

describe("renderHtml", () => {
  test("produces HTML with closing body tag", () => {
    const html = renderHtml(FIXTURE);
    expect(html).toContain("</body>");
    expect(html).toContain("</html>");
  });
});

describe("injectAutoRefresh", () => {
  test("inserts reload script before </body>", () => {
    const html = "<html><body>content</body></html>";
    const result = injectAutoRefresh(html);
    expect(result).toContain("setInterval");
    expect(result).toContain("location.reload()");
    expect(result.indexOf("setInterval")).toBeLessThan(result.indexOf("</body>"));
  });

  test("uses provided interval", () => {
    const html = "<html><body></body></html>";
    const result = injectAutoRefresh(html, 5000);
    expect(result).toContain("5000");
  });

  test("only replaces the first </body> occurrence", () => {
    const html = "<html><body></body></html>";
    const result = injectAutoRefresh(html);
    const count = (result.match(/<\/body>/g) ?? []).length;
    expect(count).toBe(1);
  });
});
