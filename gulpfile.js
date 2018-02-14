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
// Fallback paths to stingray executable and the folder to copy mods to
let fallbackStingrayExe = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide Mod Tools/bin/stingray_win64_dev_x64.exe';
let fallbackModsDir = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide/bundle/mods';

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
gulp.task('create', (callback) => {
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
gulp.task('build', (callback) => {

	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);

	console.log('Mods to build:');
	modNames.forEach(modName => console.log('- ' + modName));
	console.log();

	getPaths().then(paths => {

		let promise = Promise.resolve();	
		modNames.forEach(modName => {
			if(modName){
		    	promise = promise.then(() => buildMod(paths, modName, !leaveTemp, verbose));
			}
		});
		return promise;
	})
	.then(() => callback());
});

// Watches for changes in specified mods and builds them whenever they occur
// gulp watch [-m "mod1; mod2;mod3"] [--verbose] [-t] 
gulp.task('watch', (callback) => {
	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);
	getPaths().then(paths => {
		modNames.forEach((modName) => {
			console.log('Watching ', modName, '...');
			gulp.watch([modName, '!' + modName + '/*.tmp'], buildMod.bind(null, paths, modName, !leaveTemp, verbose));
		});
		return callback();
	});
});


//////////////

// Returns a promise with specified registry entry value
function getRegistryValue(key, value) {

	return new Promise((resolve, reject) => {

		let spawn = child_process.spawn(
			'REG',
			['QUERY', key, '/v', value],
			{windowsVerbatimArguments: true}
		);

		let result = "";

		spawn.stdout.on('data', (data) => {
			result += String(data);
		});

		spawn.on('error', (err) => {
			reject(err);
		});

		spawn.on('close', (code) => {
			if(code || !result){
				reject(code);
				return;
			}
			try{
				result = result.split('\r\n')[2].split('    ')[3];
			}
			catch(e){
				reject();
			}
			resolve(result);
		});
	});
}

// Returns a promise with paths to mods dir and stingray exe
function getPaths(){
	return new Promise((resolve, reject) => {
		let appKey = '"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App 235540"';
		let sdkKey = '"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App 718610"';
		let value = '"InstallLocation"';

		let modsDir = fallbackModsDir;
		let stingrayExe = fallbackStingrayExe;
		getRegistryValue(appKey, value)
			.catch(err => {
				console.log('Vermintide directory not found, using fallback.');
			})
			.then(appPath => {
				if(appPath) {
					modsDir = path.join(appPath, 'bundle/mods');
				}
				return getRegistryValue(sdkKey, value);
			})
			.catch(err => {
				console.log('Vermintide mod SDK directory not found, using fallback.');
			})
			.then(appPath => {
				if(appPath) {
					stingrayExe = path.join(appPath, 'bin/stingray_win64_dev_x64.exe');
				}
				console.log('Mods directory:', modsDir);
				console.log('Stingray executable:', stingrayExe);
				resolve({modsDir, stingrayExe});
			});
	});
}

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
}

// Builds modName, optionally deleting its .temp folder, and copies it to the modsDir
function buildMod(paths, modName, removeTemp = true, verbose = false) {
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
				_buildMod(paths, modName, resolve, verbose);
			});
		}
		else {
			if(tempExists) {
				console.log('.temp folder found and will be overwritten');
			}
			_buildMod(paths, modName, resolve, verbose);
		}
	});
}

// Actually builds the mod, copies it to the modsDir
function _buildMod(paths, modName, resolve, verbose = false) {
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
		paths.stingrayExe, 
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

	stingray.on('error', (err) => {
		console.log(rmn(err));
		console.log("Building failed.\n");
		resolve();
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
					return resolve();
		    	}
			    moveMod(modName, buildDir, paths.modsDir, resolve);
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
	});
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
