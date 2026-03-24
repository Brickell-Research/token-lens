import { costUsd, displayWidth } from "../token";
import type { Node } from "../types";

export function annotate(nodes: Node[], depth = 0): void {
  for (const node of nodes) {
    node.depth = depth;
    annotate(node.children, depth + 1);
    const childTokens = node.children.reduce((sum, c) => sum + (c.subtreeTokens ?? 0), 0);
    const childCost = node.children.reduce((sum, c) => sum + (c.subtreeCost ?? 0), 0);
    node.subtreeTokens = Math.max(displayWidth(node.token), 1) + childTokens;
    node.subtreeCost = costUsd(node.token) + childCost;
  }
}
