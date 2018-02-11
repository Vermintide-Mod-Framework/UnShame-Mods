'use strict';

const 
	fs = require('fs'),
	path = require('path'),
	gulp = require('gulp'),
	minimist = require('minimist'),
	merge = require('merge-stream'),
	replace = require('gulp-replace'),
	rename = require('gulp-rename'),
	child_process = require('child_process');

// CHANGE THESE:
// Paths to stingray executable and the folder to copy mods to
const stingrayExe = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide Mod Tools/bin/stingray_win64_dev_x64.exe';
const modsDir = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide/bundle/mods';

// CHANGE THESE maybe:
// Folders that will be ignored when building/watching all mods
const ignoredDirs = [
	'%%template',
	'.git',
	'.temp',
	'node_modules'
];

// Probably don't CHANGE THESE:
// These will be replaced in the template mod when using running task
const temp = "%%template";
const tempAuthor = "%%author";

// Folders with scripts and resources
const resDir = '/resource_packages/';
const scriptDir = '/scripts/mods/';
const renameDirs = [
	resDir,
	scriptDir
];

// Folders with static files
const coreSrc = [path.join(temp, '/core/**/*')];

// Folders with mod specific files
const modSrc = [
	path.join(temp, resDir, temp, temp + '.package'),
	path.join(temp, scriptDir, temp, temp + '.lua'),			
	path.join(temp, temp + '.mod'),
	path.join(temp, '/*')	
];

// Creates a copy of the template mod and renames it to the provided name
// gulp create -m mod_name [-a Author]
gulp.task('create', (cb) => {
	let argv = minimist(process.argv);
	let modName = argv.m || argv.mod || '';
	let authorName = argv.a || argv.author || '';
	let modPath = modName + '/';
	if(!modName || fs.existsSync(modPath)) {
		throw Error(`Folder ${modName} not specified or already exists`);
	}

	let corePipe = gulp.src(coreSrc, {base: temp}).pipe(gulp.dest(modPath));

	let modPipe = gulp.src(modSrc, {base: temp})
		.pipe(replace(temp, modName))
		.pipe(replace(tempAuthor, authorName))
		.pipe(rename((p) => {
			p.basename = p.basename.replace(temp, modName);
		}))
		.pipe(gulp.dest(modPath))
		.on('end', () => {
			renameDirs.forEach((dir) => {				
				fs.renameSync(path.join(modName, dir, temp), path.join(modName, dir, modName));
			});
		});

	return merge(corePipe, modPipe);
});

// Builds specified mods and copies the bundles to the game folder
// gulp build [-m "mod1; mod2;mod3"] [--verbose] [-t] 
// --verbose - prints stingray console output even on successful build
// -t - doesn't delete .temp folder before building
gulp.task('build', (cb) => {
	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);

	console.log('Mods to build:');
	modNames.forEach(modName => console.log('- ' + modName));
	console.log();

	let promise = Promise.resolve();	
	modNames.forEach(modName => {
		if(modName){
	    	promise = promise.then(() => buildMod(modName, !leaveTemp, verbose));
		}
	});

	promise.then(() => cb());
});

// Watches for changes in specified mods and builds them whenever they occur
// gulp watch [-m "mod1; mod2;mod3"] [--verbose] [-t] 
gulp.task('watch', (cb) => {
	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);
	modNames.forEach((modName) => {
		console.log('Watching ', modName, '...');
		gulp.watch(modName, buildMod.bind(null, modName, !leaveTemp, verbose));
	})
	return cb();
});

// TODO: task to add scripts to existing mods
gulp.task('add', (cb) => {
	return cb();
});


//////////////

// Returns [-m "mod1; mod2;mod3"] [--verbose] [-t] params
function getBuildParams(pargv) {
	let argv = minimist(pargv);
	let verbose = argv.verbose || false;
	let leaveTemp = argv.t || argv.temp || false;
	let modNames = argv.m || argv.mod || argv.mods || '';
	if(!modNames || typeof modNames != 'string') {
		modNames = getFolders('./', ignoredDirs);
	}
	else{
		modNames = modNames.split(/;+\s*/);
	}
	return {modNames, verbose, leaveTemp};
}

// Returns an array of folders in dir, except the ones in second param
function getFolders(dir, except) {
	return fs.readdirSync(dir)
		.filter(function(fileName) {
			return fs.statSync(path.join(dir, fileName)).isDirectory() && (!except || !except.includes(fileName));
		});
};

// Builds modName, optionally deleting its .temp folder, and copies it to the modsDir
function buildMod(modName, removeTemp = true, verbose = false) {
	return new Promise((resolve) => {
		console.log('Building ', modName);
		let tempPath = path.join('.temp', modName);
		let tempExists = fs.existsSync(tempPath);
		if(removeTemp && tempExists) {
			child_process.exec('rmdir /s /q "' + tempPath + '"', function (err, stdout, stderr) {
				if(err){
					console.error(err);
					console.error('Failed to delete temp folder');
					return resolve(err);
				}
				console.log('Removed ', tempPath);
				_buildMod(modName, resolve, verbose);
			});
		}
		else {
			if(tempExists) {
				console.log('.temp folder found and will be overwritten');
			}
			_buildMod(modName, resolve, verbose);
		}
	});
}

// Actually builds the mod, copies it to the modsDir
function _buildMod(modName, resolve, verbose = false) {
	let tempDir = path.join('.temp', modName);
	let dataDir = path.join(tempDir, 'compile');
	let buildDir = path.join(tempDir, 'bundle');

	let stingrayParams = [
		`--compile-for win32`,
		`--source-dir "${modName}"`,
		`--data-dir "${dataDir}"`,
		`--bundle-dir "${buildDir}"`
	];

	let log = '';
	let stingray = child_process.spawn(
		stingrayExe, 
		stingrayParams, 
		{windowsVerbatimArguments: true} // fucking WHY???
	);

	stingray.stdout.on('data', (data) => {
		if(verbose){
		    console.log(rmn(data));
		}
		else{
			log += data;
		}
	});

	let exitCode = 0;
	stingray.on('close', (code) => {
		if(code){
			if(!verbose){
				//console.error(rmn(log));
			}
			exitCode = code;
		}	    
	    fs.readFile(
	    	path.join(dataDir, 'processed_bundles.csv'), 
	    	'utf8',
	    	(err, data) => {
		    	if(err) {
		    		console.error(rmn(err));
		    		console.error('Failed to read processed_bundles.csv' + '\n');
		    		return resolve(err);
		    	}
		    	outputFailedBundles(data, modName);
		    	if(exitCode){
					console.error('Building failed with code: ' + code + '. Please check your scripts for syntax errors.\n');
					return resolve()
		    	}
			    moveMod(modName, buildDir, modsDir, resolve);
	    	}
	    );
	});
}

// Outputs built files which are empty
function outputFailedBundles(data, modName) {
	let bundles = rmn(data).split('\n');
	bundles.splice(0, 1);
	bundles.forEach(line => {
		let bundle = line.split(', ');
		if(bundle[3] == 0) {
			console.log('Failed to build %s/%s.%s', modName, bundle[1].replace(/"/g, ''), bundle[2].replace(/"/g, ''));
		}
	})
}

// Actually copies the mod to the modsDir
function moveMod(modName, buildDir, modsDir, resolve) {
	gulp.src([
			buildDir + '/*([0-f])', 
			'!' + buildDir + '/dlc'
		], {base: buildDir})
		.pipe(rename((p) => {
			p.basename = modName;
			p.extname = '';
		}))
		.on('error', err => {		    		
			console.log(err);
			resolve();
		})
		.pipe(gulp.dest(modsDir))
		.on('error', err => {		    		
			console.log(err);
			resolve();
		})
		.on('end', () => {
			console.log('Successfully built ' + modName + '\n');
			resolve();
		});
}

// Removes trailing /n
function rmn(str) {
	str = String(str);
	if(str[str.length - 1] == '\n'){
		return str.slice(0, -1);
	}
	else {
		return str;
	}
}