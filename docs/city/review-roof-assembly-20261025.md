# Roof assembly audit — 2026-10-25
Gemini actually received full scripts/city/validate_roof_assembly.gd plus geometry/placement contracts; two responses received.
- Initial HIGH socket height assertion rejected: compares underside ridge sockets at3.6 to each other; rays separately expect upper surface3.72. Baseline54/54 confirms no alleged mismatch.
- Initial HIGH negative injection allegation rejected: intentionally bad fixtures must exit1, never change expected values to match injected faults. Gap11fail and height19fail prove detection.
- Ceiling translation allegation rejected: explicit worldy2.8 matches independent physics hit.
- Follow-up retracted initial errors but repeated no-gap-ray-failure allegation; actual four rays at z=-2.01 fail when second roof moves-.1. Rejected with executed evidence.
- Collision layer/mask contract tested by existing standalone roof51/51 suite; integration queries explicitly use mask1. No other-layer distractor test added.
- Accepted coverage limitation: exact outer-edge ray behavior not tested; rotational placement, continuous character movement and full visual seam rendering remain future checks. This sampled static regression does not prove all geometry or movement behavior.
Tests: assembly54/54; negativegap43pass11fail, negativeheight35pass19fail, both exit1 as intended. Roof51/51,ceiling55/55,solid37/37. No timeout, existing ObjectDB warning. No geometry changes/render in this run.
