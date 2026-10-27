extends SceneTree
const G=preload("res://tools/automation_lock.gd")
const L=preload("res://scripts/assets/lsx_decoder.gd")
const PATH="res://assets/src/clothing_c5/top.lsx"
const EXPECTED="b71d2d84ca869f7492785ccd2461c0992e40112c0200cc17e8eb0f43b79627e6"
func _init():
    var args=OS.get_cmdline_user_args()
    if args.size()!=1 or not G.owns(args[0]):quit(2);return
    if FileAccess.get_sha256(PATH)!=EXPECTED:quit(3);return
    if FileAccess.get_sha256("res://tools/blender/clothing_c5.py")!="6a98936f2ea3c7e8bfa25a43e512cbe603c8e1cdb79a3fcce07697523f07e6ef":quit(4);return
    var old=FileAccess.get_file_as_string(PATH)
    var decoded=L.decode(old)
    var raw=Marshalls.base64_to_raw(old.strip_edges()).decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_DEFLATE)
    var offset=4+raw.decode_u32(0)
    var before=raw.duplicate()
    var bone_ids={}
    for i in decoded.head.bones.size():bone_ids[decoded.head.bones[i].name]=i
    var allowed={}
    var count=0
    for part in decoded.head.parts:
        if not String(part.name).begins_with("C5__top__") or not ("__sleeve_" in part.name):continue
        var suffix="l" if String(part.name).ends_with("__sleeve_1") else "r"
        if not String(part.name).ends_with("__sleeve_1") and not String(part.name).ends_with("__sleeve_-1"):quit(5);return
        var n=int(part.nv)
        if n!=70 or int(part.bi[1])!=2*n or int(part.bw[1])!=n:quit(6);return
        var positions=L._positions(part,decoded.blob,n)
        var elbow=float(decoded.head.bones[bone_ids["forearm_"+suffix]].head[1])
        var wrist=float(decoded.head.bones[bone_ids["hand_"+suffix]].head[1])
        for i in n:
            # Match source ring height before quantization; never re-author positions.
            var y=positions[i].y
            var nearest=INF
            var authored=0.0
            for ring in [1.164,1.096,1.008,.909,.875]:
                if absf(y-ring)<nearest:nearest=absf(y-ring);authored=ring
            if nearest>.0001:quit(7);return
            var f=clampf((elbow+.06-authored)/.12,0,1)
            var h=clampf((wrist+.04-authored)/.08,0,1)
            var weights=[[1-f,bone_ids["upper_arm_"+suffix]],[f*(1-h),bone_ids["forearm_"+suffix]],[f*h,bone_ids["hand_"+suffix]]]
            weights.sort_custom(func(a,b): return a[0]>b[0] if a[0]!=b[0] else a[1]>b[1])
            var sumw=weights[0][0]+weights[1][0]
            var bi=offset+int(part.bi[0])
            var bw=offset+int(part.bw[0])
            raw[bi+i]=weights[0][1];raw[bi+n+i]=weights[1][1]
            raw[bw+i]=int(round(weights[0][0]/sumw*255))
            allowed[bi+i]=true;allowed[bi+n+i]=true;allowed[bw+i]=true
        count+=1
    if count!=22:quit(8);return
    var changed=0
    for i in raw.size():
        if raw[i]!=before[i]:
            if not allowed.has(i):quit(9);return
            changed+=1
    var encoded=Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
    if L.decode(encoded).is_empty():quit(10);return
    var backup="res://previews/"+args[0]+"-top-before.lsx"
    if not G.owns(args[0]) or FileAccess.get_sha256(PATH)!=EXPECTED or FileAccess.file_exists(backup):quit(11);return
    if DirAccess.copy_absolute(PATH,backup)!=OK:quit(12);return
    if not G.owns(args[0]) or FileAccess.get_sha256(PATH)!=EXPECTED:quit(13);return
    var file=FileAccess.open(PATH,FileAccess.WRITE)
    if file==null:quit(14);return
    file.store_string(encoded);file.close()
    print("MIGRATED sleeves=",count," changed_weight_bytes=",changed," nonweight_bytes_unchanged=true SHA=",FileAccess.get_sha256(PATH))
    quit(0)
