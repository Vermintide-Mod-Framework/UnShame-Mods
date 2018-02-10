'use strict';

const 
	fs = require('fs'),
	path = require('path'),
	gulp = require('gulp'),
	minimist = require('minimist'),
	merge = require('merge-stream'),
	replace = require('gulp-replace'),
	rename = require('gulp-rename'),
	file = require('gulp-file'),
	child_process = require('child_process');

const stingrayExe = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide Mod Tools/bin/stingray_win64_dev_x64.exe';
const modsDir = 'E:/SteamLibrary/steamapps/common/Warhammer End Times Vermintide/bundle/mods';

const ignoredDirs = [
	'%%template',
	'.git',
	'.temp',
	'node_modules'
];

const temp = "%%template";
const tempAuthor = "%%author";

const resDir = '/resource_packages/';
const scriptDir = '/scripts/mods/';
const renameDirs = [
	resDir,
	scriptDir
];

const coreSrc = [path.join(temp, '/core/**/*')];
const modSrc = [
	path.join(temp, resDir, temp, temp + '.package'),
	path.join(temp, scriptDir, temp, temp + '.lua'),			
	path.join(temp, temp + '.mod'),
	path.join(temp, '/*')	
];

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

gulp.task('build', (cb) => {
	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);

	console.log('Mods to build:');
	modNames.forEach(modName => console.log('- ' + modName));
	console.log();

	var promise = Promise.resolve();	
	modNames.forEach(modName => {
		if(modName){
	    	promise = promise.then(() => buildMod(modName, !leaveTemp, verbose));
		}
	});

	promise.then(() => cb());
});

gulp.task('watch', (cb) => {
	let {modNames, verbose, leaveTemp} = getBuildParams(process.argv);
	modNames.forEach((modName) => {
		gulp.watch(modName, buildMod.bind(null, modName, !leaveTemp, verbose));
	})
	return cb();
});

function getBuildParams(pargv) {
	let argv = minimist(pargv);
	let verbose = argv.verbose || false;
	let leaveTemp = argv.t || argv.temp || false;
	let modNames = argv.m || argv.mod || argv.mods || '';
	if(!modNames) {
		modNames = getFolders('./', ignoredDirs);
	}
	else{
		modNames = modNames.split(/;+\s*/);
	}
	return {modNames, verbose, leaveTemp};
}

gulp.task('add', (cb) => {
	return cb();
});

function getFolders(dir, except) {
	return fs.readdirSync(dir)
		.filter(function(fileName) {
			return fs.statSync(path.join(dir, fileName)).isDirectory() && (!except || !except.includes(fileName));
		});
};


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

	stingray.on('close', (code) => {
		if(code){
			if(!verbose){
				console.error(rmn(log));
			}
			console.error('Building failed with code: ' + code + '\n');
			return resolve();
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
		    	console.log(rmn(data));
		    	moveMod(modName, buildDir, modsDir, resolve);
	    	}
	    );
	});
}

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

function rmn(str) {
	str = String(str);
	if(str[str.length - 1] == '\n'){
		return str.slice(0, -1);
	}
	else {
		return str;
	}
}