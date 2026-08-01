extends GameItemPlaceable
class_name GameItemFloor

## Floors go on layer 2 and are otherwise ordinary placeables. The use() override that
## used to be here duplicated GameItemPlaceable.use() verbatim, which would have meant
## floors quietly skipping the build-xp award; it is gone rather than re-copied.
