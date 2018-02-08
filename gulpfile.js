'use strict';

const 
	fs = require('fs'),
	path = require('path'),
	gulp = require('gulp'),
	minimist = require('minimist'),
	merge = require('merge-stream'),
	replace = require('gulp-replace'),
	rename = require('gulp-rename'),
	file = require('gulp-file');

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
			p.basename = p.basename.replace(temp, modName)
		}))
		.pipe(gulp.dest(modPath))
		.on('end', () => {
			renameDirs.forEach((dir) => {				
				fs.renameSync(path.join(modName, dir, temp), path.join(modName, dir, modName));
			})
		});

	return merge(corePipe, modPipe);
});

gulp.task('build', (cb) => {
	return cb();
});

gulp.task('watch', (cb) => {
	return cb();
});

gulp.task('add', (cb) => {
	return cb();
});
