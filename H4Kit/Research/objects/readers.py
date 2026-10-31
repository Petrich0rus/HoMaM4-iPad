import sys; sys.path.insert(0,".")
import re,pickle
exec(open('slot0.py').read().split("print('=====')")[0].split("seen={}")[0])
def ctor_of(s0):
    f=func(s0,400); txt='\n'.join(f)
    calls=[c for c in re.findall(r'calll\t0x([0-9a-f]+)',txt)]
    c=[x for x in calls if x not in ('8d98a0','411f50','4f93b0','4f9490','4120f0','404ba0')]
    return int(c[0],16) if c else None
def vts0(ctor):
    f=func(ctor,3000); res=[]
    for l in f:
        m=re.search(r'movl\t\$0x([0-9a-f]+), \((%\w+)\)',l)
        if m:
            v=int(m.group(1),16)
            if 0x970000<=v<0xa46000:
                n=rtti(v)
                if n: res.append((m.group(2),n[4:-2],hex(v),hex(u32(v+0x90))))
    return res
names={0:'abandoned_mine',1:'abbey',2:'academy',3:'arena',4:'artifact',5:'artifact_pile',6:'blacksmith',7:'blattner_stone',8:'border_gate',9:'border_guard',10:'bridge',11:'buoy',12:'campfire',13:'carryover_hero',14:'cartographer',15:'chain',16:'clover_field',17:'coliseum',18:'conservatory',19:'corpse',20:'creature_bank',21:'creature_dwelling',22:'decorative',23:'deletion_marker',24:'dolphin_school',25:'event_trigger',26:'exhausted_mine',27:'eye_of_the_magi',28:'faerie_ring',29:'ferry',30:'flotsam',31:'fountain',32:'garrison',33:'gateway',34:'hut_of_the_magi',35:'idol_of_fortune',36:'kelp_beds',37:'keymaster_tent',38:'lighthouse',39:'magic_gem',40:'mana_recharger',41:'material_pile',42:'medicine_wagon',43:'mercenary_camp',44:'mine',45:'movement_booster',46:'nothing',47:'obelisk',48:'obelisk_marker',49:'ocean_bottle',50:'outpost',51:'oyster',52:'pandoras_box',53:'path_arrow',54:'pathfinder',55:'port',56:'prison',57:'quest_gate',58:'quest_guard',59:'rainbow',60:'random_artifact',61:'random_creature_dwelling',62:'random_conservatory',63:'random_material_pile',64:'random_monster',65:'random_potion',66:'random_random_monster',67:'random_shrine',68:'random_staff',69:'random_teacher',70:'random_temple',71:'random_tome',72:'random_town',73:'random_weekly_material_generator',74:'sacred_grove',75:'sanctuary',76:'school',77:'seers_hut',78:'selection_ring',79:'ship',80:'shipwreck_survivor',81:'shipyard',82:'shrine',83:'sign',84:'sphinx',85:'stagecoach',86:'subterranean_gate',87:'system_object',88:'tavern',89:'teacher',90:'teleporter_entrance',91:'teleporter_exit',92:'temple',93:'?93',94:'tower',95:'town',96:'trading_post',97:'training_grounds',98:'treasure',99:'tree_of_knowledge',100:'vein',101:'victory_flag',102:'weekly_material_generator',103:'windmill',104:'whirlpool'}
cache={}
res={}
for cls,sub,reg,vt,s0 in rows:
    c=ctor_of(s0)
    if c is None:
        print(cls,sub,names.get(cls),'slot0',hex(s0),'NOCTOR'); continue
    if c not in cache: cache[c]=vts0(c)
    v=cache[c]
    last=v[-1] if v else None
    print(cls,sub,names.get(cls),'slot0',hex(s0),'ctor',hex(c),'|',[(x[1],x[2],x[3]) for x in v if True][-3:])
