-- VEHICLE DATA
-- collected from native scrubs, github repos and google
-- gathered as much as we can. possible we missed some things but wont know for sure until known to us

veh_data = {
    VEHICLE_CLASSES = {
        [0]="COMPACT",[1]="SEDAN",[2]="SUV",[3]="COUPE",[4]="MUSCLE",[5]="SPORT_CLASSIC",[6]="SPORT",
        [7]="SUPER",[8]="MOTORCYCLE",[9]="OFF_ROAD",[10]="INDUSTRIAL",[11]="UTILITY",[12]="VAN",
        [13]="CYCLE",[14]="BOAT",[15]="HELICOPTER",[16]="PLANE",[17]="SERVICE",[18]="EMERGENCY",
        [19]="MILITARY",[20]="COMMERCIAL",[21]="TRAIN",
    },
    WHEEL_TYPES = {
        [0]="STOCK",[1]="SPORT",[2]="MUSCLE",[3]="LOWRIDER",[4]="SUV",[5]="OFFROAD",
        [6]="TUNER",[7]="BIKE",[8]="HIEND",[9]="BENNY_OR_BESPoke",[10]="F1",[11]="SUPERMOD",
        [12]="TRUCK",
    },
    PLATE_TYPES = {
        [0]="FRONT_AND_BACK_PLATES",[1]="FRONT_PLATES",[2]="BACK_PLATES",[3]="NONE",[4]="UNKNOWN",
    },
    KNOWN_BONES = {
        "chassis","bonnet","boot","bumper_f","bumper_r","wing_lf","wing_rf",
        "door_dside_f","door_pside_f","door_dside_r","door_pside_r",
        "window_lf","window_rf","window_lr","window_rr","windscreen","windscreen_r",
        "headlight_l","headlight_r","indicator_lf","indicator_rf",
        "taillight_l","taillight_r","brakelight_l","brakelight_r","brakelight_m",
        "neon_l","neon_r","neon_f","neon_b","engine","exhaust","exhaust_2",
        "seat_dside_f","seat_pside_f","steeringwheel","dials",
        "wheel_lf","wheel_rf","wheel_lr","wheel_rr","wheelmesh_lf","wheelmesh_rf",
        "hub_lf","hub_rf","hub_lr","hub_rr",
        "chassis_dummy","bodyshell","interiorlight","platelight","overheat","overheat_2"
    },
}