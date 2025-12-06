package objects;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.util.FlxSort;

import backend.animation.PsychAnimationController;
import backend.animate.AnimateCharacter;
import backend.animate.AnimateZipReader;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;

#if flxanimate
import flxanimate.FlxAnimate;
#end

/**
 * Character.hx
 * FINAL VERSION – PNG + ATLAS + ZIP
 *
 * ZIP characters:
 *    mods/<mod>/animate/<file>.zip
 *
 * JSON can specify ZIP by:
 *    "renderType": "swf"
 * OR
 *    "animateZip": "crud_bf.zip"
 */

typedef AnimArray = {
    var anim:String;
    var name:String;
    var fps:Int;
    var loop:Bool;
    var indices:Array<Int>;
    var offsets:Array<Int>;
};

typedef CharacterFile = {
    var animations:Array<AnimArray>;
    var image:String;
    var scale:Float;
    var sing_duration:Float;
    var healthicon:String;
    var position:Array<Float>;
    var camera_position:Array<Float>;
    var flip_x:Bool;
    var no_antialiasing:Bool;
    var healthbar_colors:Array<Int>;
    var vocals_file:String;

    @:optional var animateZip:String;
    @:optional var renderType:String;
};

class Character extends FlxSprite
{
    public static final DEFAULT_CHARACTER:String = "bf";

    public var curCharacter:String = DEFAULT_CHARACTER;
    public var isPlayer:Bool = false;

    public var animOffsets:Map<String, Array<Float>> = new Map();
    public var animationsArray:Array<AnimArray> = [];

    public var singDuration:Float = 4;
    public var holdTimer:Float = 0;
    public var heyTimer:Float = 0;

    public var specialAnim:Bool = false;
    public var skipDance:Bool = false;
    public var danceIdle:Bool = false;
    public var danced:Bool = false;

    public var healthIcon:String = "face";
    public var healthColorArray:Array<Int> = [255, 0, 0];

    public var positionArray:Array<Float> = [0, 0];
    public var cameraPosition:Array<Float> = [0, 0];

    public var jsonScale:Float = 1;
    public var noAntialiasing:Bool = false;

    public var missingCharacter:Bool = false;
    public var missingText:FlxText;

    var _lastPlayedAnimation:String = "idle";

    // -------------------------------------
    // Renderer flags
    // -------------------------------------
    public var isAnimateZIP:Bool = false;
    public var isAnimateAtlas:Bool = false;

    public var animateZIPChar:AnimateCharacter;
    public var atlas:FlxAnimate;

    // -------------------------------------
    // Constructor
    // -------------------------------------
    public function new(x:Float, y:Float, ?character:String="bf", ?isPlayer:Bool=false)
    {
        super(x, y);
        this.isPlayer = isPlayer;

        animation = new PsychAnimationController(this);
        changeCharacter(character);
    }

    // -------------------------------------
    // Load JSON
    // -------------------------------------
    public function changeCharacter(char:String)
    {
        curCharacter = char;
        animOffsets = [];
        animationsArray = [];

        var jsonPath = Paths.getPath("characters/" + char + ".json", TEXT);

        #if MODS_ALLOWED
        if (!FileSystem.exists(jsonPath))
        #else
        if (!Assets.exists(jsonPath))
        #end
        {
            jsonPath = Paths.getSharedPath("characters/" + DEFAULT_CHARACTER + ".json");
            missingCharacter = true;

            missingText = new FlxText(0,0,300,'ERROR:\n' + char + '.json',16);
            missingText.alignment = CENTER;
        }

        var json:Dynamic =
            #if MODS_ALLOWED Json.parse(File.getContent(jsonPath));
            #else Json.parse(Assets.getText(jsonPath));
            #end

        loadCharacterFile(json);
        dance();
    }

    // -------------------------------------
    // Main loader (ZIP → ATLAS → PNG)
    // -------------------------------------
    public function loadCharacterFile(json:Dynamic)
    {
        isAnimateZIP = false;
        isAnimateAtlas = false;

        jsonScale = json.scale;
        positionArray = json.position;
        cameraPosition = json.camera_position;
        healthIcon = json.healthicon;
        singDuration = json.sing_duration;

        flipX = (json.flip_x != isPlayer);

        noAntialiasing = (json.no_antialiasing == true);
        antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

        // ---------------------------------------------------------
        // 1. ZIP MODE (renderType:"swf" OR animateZip)
        // ---------------------------------------------------------
        if (json.renderType == "swf" || json.animateZip != null)
        {
            var zipName = (json.animateZip != null ? json.animateZip : json.image + ".zip");
            var zipPath = Paths.modFolders("animate/" + zipName);

            if (FileSystem.exists(zipPath))
            {
                trace("Loading ZIP: " + zipPath);
                isAnimateZIP = true;

                animateZIPChar = new AnimateCharacter(zipPath);

                for (a in json.animations)
                {
                    var off = a.offsets;
                    addOffset(a.anim, off[0], off[1]);
                }

                if (json.scale != null) animateZIPChar.scale.set(json.scale, json.scale);

                return;
            }
            else
                trace("ERROR ZIP NOT FOUND: " + zipPath);
        }

        // ---------------------------------------------------------
        // 2. ATLAS MODE
        // ---------------------------------------------------------
        #if flxanimate
        var animJSON = Paths.getPath("images/" + json.image + "/Animation.json", TEXT);
        var existsAtlas =
            #if MODS_ALLOWED FileSystem.exists(animJSON);
            #else Assets.exists(animJSON);
            #end

        if (existsAtlas)
        {
            isAnimateAtlas = true;
            atlas = new FlxAnimate();
            atlas.showPivot = false;

            Paths.loadAnimateAtlas(atlas, json.image);

            for (a in json.animations)
            {
                addOffset(a.anim, a.offsets[0], a.offsets[1]);

                if (a.indices.length > 0)
                    atlas.anim.addBySymbolIndices(a.anim, a.name, a.indices, a.fps, a.loop);
                else
                    atlas.anim.addBySymbol(a.anim, a.name, a.fps, a.loop);
            }

            return;
        }
        #end

        // ---------------------------------------------------------
        // 3. PNG MODE
        // ---------------------------------------------------------
        frames = Paths.getMultiAtlas(json.image.split(","));
        animationsArray = json.animations;

        for (a in animationsArray)
        {
            if (a.indices.length > 0)
                animation.addByIndices(a.anim, a.name, a.indices, "", a.fps, a.loop);
            else
                animation.addByPrefix(a.anim, a.name, a.fps, a.loop);

            addOffset(a.anim, a.offsets[0], a.offsets[1]);
        }

        if (json.scale != null)
            scale.set(json.scale, json.scale);

        updateHitbox();
    }

    // -------------------------------------
    // Add JSON offset
    // -------------------------------------
    public function addOffset(name:String, x:Float, y:Float)
        animOffsets.set(name, [x,y]);

    // -------------------------------------
    // Check animation
    // -------------------------------------
    public function hasAnimation(name:String):Bool
        return animOffsets.exists(name);

    // -------------------------------------
    // playAnim (ZIP → ATLAS → PNG)
    // -------------------------------------
    public function playAnim(name:String, force:Bool=false, reversed:Bool=false, frame:Int=0)
    {
        specialAnim = false;
        _lastPlayedAnimation = name;

        // ZIP system
        if (isAnimateZIP)
        {
            animateZIPChar.play(name);

            if (animOffsets.exists(name))
                offset.set(animOffsets[name][0], animOffsets[name][1]);

            applyGFDance(name);
            return;
        }

        // ATLAS system
        #if flxanimate
        if (isAnimateAtlas)
        {
            atlas.anim.play(name, force, reversed, frame);
            atlas.update(0);

            if (animOffsets.exists(name))
                offset.set(animOffsets[name][0], animOffsets[name][1]);

            applyGFDance(name);
            return;
        }
        #end

        // PNG system
        animation.play(name, force, reversed, frame);

        if (animOffsets.exists(name))
            offset.set(animOffsets[name][0], animOffsets[name][1]);

        applyGFDance(name);
    }

    inline function applyGFDance(name:String)
    {
        if (!curCharacter.startsWith("gf") && curCharacter != "gf") return;

        if (name == "singLEFT") danced = true;
        else if (name == "singRIGHT") danced = false;

        if (name == "singUP" || name == "singDOWN") danced = !danced;
    }

    // -------------------------------------
    // update() — ZIP → ATLAS → PNG
    // -------------------------------------
    override function update(elapsed:Float)
    {
        // ZIP MODE
        if (isAnimateZIP)
        {
            animateZIPChar.update(elapsed);

            handleHeyTimer(elapsed);
            handleSingTimer(elapsed);

            super.update(elapsed);
            return;
        }

        // ATLAS MODE
        #if flxanimate
        if (isAnimateAtlas)
        {
            atlas.update(elapsed);

            handleHeyTimer(elapsed);
            handleSingTimer(elapsed);

            super.update(elapsed);
            return;
        }
        #end

        // PNG MODE
        handleHeyTimer(elapsed);
        handleSingTimer(elapsed);

        super.update(elapsed);
    }

    function handleHeyTimer(elapsed:Float)
    {
        if (heyTimer > 0)
        {
            heyTimer -= elapsed;
            if (heyTimer <= 0)
            {
                if (specialAnim && (getAnimationName() == "hey" || getAnimationName() == "cheer"))
                    dance();

                specialAnim = false;
                heyTimer = 0;
            }
        }
    }

    function handleSingTimer(elapsed:Float)
    {
        if (getAnimationName().startsWith("sing"))
            holdTimer += elapsed;
        else if (isPlayer)
            holdTimer = 0;

        if (!isPlayer && holdTimer >= Conductor.stepCrochet * 0.0011 * singDuration)
        {
            dance();
            holdTimer = 0;
        }
    }

    inline public function getAnimationName():String
        return _lastPlayedAnimation;

    // -------------------------------------
    // draw() — ZIP → ATLAS → PNG
    // -------------------------------------
    override function draw()
    {
        if (isAnimateZIP)
        {
            // copy transforms
            animateZIPChar.x = x;
            animateZIPChar.y = y;
            animateZIPChar.offset.copyFrom(offset);
            animateZIPChar.scale.copyFrom(scale);
            animateZIPChar.flipX = flipX;
            animateZIPChar.angle = angle;
            animateZIPChar.alpha = alpha;
            animateZIPChar.color = color;
            animateZIPChar.visible = visible;
            animateZIPChar.cameras = cameras;

            animateZIPChar.draw();
            return;
        }

        #if flxanimate
        if (isAnimateAtlas)
        {
            @:privateAccess {
                atlas.x = x;
                atlas.y = y;
                atlas.offset = offset;
                atlas.scale = scale;
                atlas.flipX = flipX;
                atlas.angle = angle;
                atlas.alpha = alpha;
                atlas.color = color;
                atlas.cameras = cameras;
            }
            atlas.draw();
            return;
        }
        #end

        super.draw();
    }
}
