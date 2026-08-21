# Final Blitzkrieg force-catalog approximation

The active U.S. and German unit catalogs are an operational-scale approximation of the base game *Combat Mission: Final Blitzkrieg*. They are intended to give the companion historically recognizable late-1944 divisions, regiments, battalions, companies, and platoons without reproducing Combat Mission's proprietary internal database.

## Scope

- Timeframe: October 1944 through January 1945.
- Services: U.S. Army; German Heer, Waffen-SS, and Luftwaffe Fallschirmjager.
- Strength: idealized full-strength tables of organization, not the depleted strength of a named formation on a particular day.
- Scale: divisions and regiments are retained because the companion operates above Combat Mission's tactical battle scale.
- Selection minimum: platoon. Squads and sections may exist inside an expanded formation, but cannot be added independently. Individual armored vehicles exist only in a platoon's or headquarters section's `vehicle_roster`.
- Excluded from this pass: the Downfall module and rare specialist armor such as Jagdtiger, Sturmtiger, flamethrower tanks, Sherman Jumbo, and M24 Chaffee formations.

## Source hierarchy

1. *Combat Mission: Final Blitzkrieg* manual, particularly its service and formation overview: https://ftp.matrixgames.com/pub/CombatMissionFinalBlitzkrieg/CM%20Final%20Blitzkrieg%20Manual.pdf
2. Battlefront formation and TO&E patch notes: https://community.battlefront.com/topic/122890-v101-patch-almost-here-patch-notes-inside/
3. U.S. Army wartime tables of organization and later Army historical studies. A representative official rifle-company table is available from the Combined Arms Research Library: https://cgsc.contentdm.oclc.org/digital/api/collection/p15040coll6/id/4342/download
4. German Type-44 organizational charts and KStN summaries. A representative Type-44 Panzer Division chart is available at: https://www.generalstaff.org/NAF/Pt_I_1943-1945/944gxag.pdf

## Modeling decisions

- U.S. armored divisions use three representative Combat Commands. Each contains a tank battalion, armored infantry battalion, and self-propelled artillery battalion. Historically, these commands were flexible task organizations rather than permanently fixed brigades; the grouping keeps the entire division within the companion's seven-child limit.
- U.S. airborne divisions use the four infantry regiments commonly fielded by the 82nd and 101st Airborne Divisions in the Ardennes: three parachute infantry regiments and one glider infantry regiment.
- Ordinary German Army formations omit the implied Heer prefix. Exceptional service affiliations such as Waffen-SS and Luftwaffe Fallschirmjager remain explicit while all formations stay in the single Germany nation catalog.
- Panzer IV and Panther companies use the representative late-1944 17-tank organization; Tiger and Tiger II companies use 14 tanks.
- Assault-gun batteries use ten vehicles, while Jagdpanzer IV and Hetzer companies use fourteen vehicles.
- Headquarters and administrative elements are included only where they preserve hierarchy, command identity, or vehicle accounting. Noncombat service units are generally omitted.

This file should be updated whenever a catalog composition is changed because of better in-game evidence or a more authoritative historical source.
