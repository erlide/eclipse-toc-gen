/** 
 * Copyright (c) 2015 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 */
package org.xtext.tocgen

import com.google.common.io.Files
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.io.FileWriter
import java.io.IOException
import java.io.Writer
import java.util.Arrays
import java.util.Comparator
import java.util.List
import java.nio.file.Paths

package class TocGenerator {
	def static void main(String[] args) {
		try {
			if (isHelpRequested(args)) {
				System.err.println('''
					Usage: java -jar gen_toc.jar [directory]
					
					The optional argument [directory] must point to a relative or absolute file
					system directory in which the source files are searched. The default is to
					search the current directory. The output is always generated in a subdirectory
					named "contents" in the current directory.
				''')
				System.exit(1)
			} else if (args.length === 1) {
				new TocGenerator(args.get(0), "contents").generate()
			} else {
				val s = Paths.get("").toAbsolutePath().toString();
				new TocGenerator(s, "contents").generate()
			}
		} catch (Throwable t) {
			t.printStackTrace()
			System.exit(1)
		}

	}

	def private static boolean isHelpRequested(String[] args) {
		if (args.length === 1) {
			return #["h", "-h", "help", "-help", "--help"].contains(args.get(0))
		}
		return args.length > 1
	}

	final String sourceDirName
	final String destDirName
	final String fileExtension = ".md"
	final int maxSectionLevel = 3
	int indentLevel

	new(String sourceDirName, String destDirName) {
		this.sourceDirName = sourceDirName
		this.destDirName = destDirName
	}

	def void generate() throws IOException {
		var File sourceDir = new File(sourceDirName)
		if (!sourceDir.isDirectory()) {
			System.err.println('''«sourceDirName» is not a directory.''')
			System.exit(1)
		}
		var List<File> sourceFiles = getSourceFiles(sourceDir)
		if (sourceFiles.isEmpty) {
			System.err.println('''The directory «sourceDirName» does not contain any valid input files.''')
			System.exit(1)
		}
		var File indexFile = new File('''«sourceDirName»«File.separator»index«fileExtension»''')
		if (!indexFile.exists) {
			System.err.println(
				'''The directory «sourceDirName» does not contain an index.«fileExtension» file.''')
			System.exit(1)
		}
		var String docTitle = getPart(indexFile)
		indentLevel = 0
		var File outputFile = new File('''«destDirName»«File.separator»toc.xml''')
		var FileWriter output = null
		try {
			output = new FileWriter(outputFile)
			write(output, "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>")
			write(output, "<toc topic=\"", destDirName, "/index.html\" label=\"", docTitle, "\">")
			indent(1)
			generateContent(sourceFiles, output)
			indent(-1)
			write(output, "</toc>")
		} finally {
			if(output !== null) output.close()
		}
		System.out.println('''Generated file «outputFile.getAbsolutePath()»''')
	}

	def private void generateContent(List<File> markdownFiles, Writer output) throws IOException {
		var String lastPart = null
		for (File file : markdownFiles) {
			val path = Paths.get(sourceDirName).relativize(Paths.get(file.absolutePath)).toString
			var String fileName = path.substring(0, path.length() - fileExtension.length()).replaceAll("\\\\", "/")
			var String partName = getPart(file)
			if (!partName.equals(lastPart)) {
				if (lastPart !== null) {
					indent(-1)
					write(output, "</topic>")
				}
				write(output, '''<topic label="«partName»">''')
				indent(1)
			}
			var FileReader closeable = null
			try {
				closeable = new FileReader(file)
				var BufferedReader reader = new BufferedReader(closeable)
				System.out.println('''Processing file «file.getAbsolutePath()»''')
				generateContent(fileName, reader, output)
			} finally {
				if(closeable !== null) closeable.close()
			}
			lastPart = partName
		}
		indent(-1)
		write(output, "</topic>")
	}

	def private void generateContent(String fileName, BufferedReader reader, Writer output) throws IOException {
		var int lastSectionLevel = 0
		var String line = getNextSection(reader)
		while (line !== null) {
			var String sectionName = getSectionName(line)
			if (sectionName !== null) {
				var int sectionLevel = getSectionLevel(line)
				if (lastSectionLevel === 0) {
					write(output, "<topic href=\"", destDirName, "/", fileName, ".html\" label=\"", sectionName, "\">")
					indent(1)
					lastSectionLevel = 1
				} else if (sectionLevel <= maxSectionLevel) {

					for (var int i = sectionLevel; i <= lastSectionLevel; i++) {
						indent(-1)
						write(output, "</topic>")
					}
					var String anchor = getSectionAnchor(line)
					write(output, "<topic href=\"", destDirName, "/", fileName, ".html#", anchor, "\" label=\"",
						sectionName, "\">")
					indent(1)
					if (sectionLevel > lastSectionLevel + 1)
						lastSectionLevel = sectionLevel + 1
					else
						lastSectionLevel = sectionLevel
				}

			}
			line = getNextSection(reader)
		}

		for (var int i = 1; i <= lastSectionLevel; i++) {
			indent(-1)
			write(output, "</topic>")
		}

	}

	@SuppressWarnings("resource") def private String getPart(File file) throws IOException {
		var FileReader closeable = null
		try {
			closeable = new FileReader(file)
			var BufferedReader reader = new BufferedReader(closeable)
			var String line = reader.readLine()
			var boolean firstLine = true
			while (line !== null) {
				if(line === null || firstLine && !line.startsWith("---") ||
					!firstLine && line.startsWith("---")) return ""
				if (line.startsWith("part:")) {
					return line.substring(5).trim()
				}
				line = reader.readLine()
				firstLine = false
			}

		} finally {
			if(closeable !== null) closeable.close()
		}
		return ""
	}

	def private String getNextSection(BufferedReader reader) throws IOException {
		var String line = reader.readLine()
		while (line !== null) {
			if(line.startsWith("#")) return line
			line = reader.readLine()
		}
		return null
	}

	def private int getSectionLevel(String line) {
		var int result = 0

		for (var int i = 0; i < line.length(); i++) {
			if(line.charAt(i) === Character.valueOf('#').charValue) result++ else return result
		}
		return result
	}

	def private String getSectionName(String line) {

		for (var int i = 0; i < line.length(); i++) {
			if (line.charAt(i) !== Character.valueOf('#').charValue) {
				var int anchorIndex = line.indexOf(Character.valueOf('{').charValue)
				if(anchorIndex >= i) return line.substring(i, anchorIndex).trim() else return line.substring(i).trim()
			}

		}
		return null
	}

	def private String getSectionAnchor(String line) {
		var int anchorStartIndex = line.indexOf(Character.valueOf('{').charValue)
		var int anchorEndIndex = line.indexOf(Character.valueOf('}').charValue)
		if (anchorStartIndex >= 0 && anchorEndIndex > anchorStartIndex) {
			var String result = line.substring(anchorStartIndex + 1, anchorEndIndex)
			if(result.startsWith("#")) return result.substring(1) else return result
		} else {
			var String sectionName = getSectionName(line).toLowerCase()
			var StringBuilder result = new StringBuilder()

			for (var int i = 0; i < sectionName.length(); i++) {
				var char c = sectionName.charAt(i)
				if (Character.isLetterOrDigit(c) || c === Character.valueOf('-').charValue) {
					result.append(c)
				} else if (c === Character.valueOf(' ').charValue) {
					result.append(Character.valueOf('-').charValue)
				}

			}
			return result.toString()
		}
	}

	def private Writer write(Writer writer, String... line) throws IOException {

		for (var int i = 0; i < indentLevel; i++) {
			writer.write(Character.valueOf('	').charValue)
		}

		for (var int j = 0; j < line.length; j++) {
			writer.write({
				val _rdIndx_line = j
				line.get(_rdIndx_line)
			})
		}
		writer.write(Character.valueOf('\n').charValue)
		return writer
	}

	def private void indent(int x) {
		indentLevel += x
	}

	def private List<File> getSourceFiles(File sourceDir) {
		val files = Files.fileTreeTraverser.breadthFirstTraversal(sourceDir)
		var File[] filteredFiles = files.filter [ File file |
			return file.isFile() && file.name.endsWith(fileExtension) && !file.name.startsWith("index")
		]
		Arrays.sort(filteredFiles,(
			[File file1, File file2|return file1.name.compareTo(file2.name)] as Comparator<File>))
		return Arrays.asList(filteredFiles)
	}

}
