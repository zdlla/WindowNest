import sys,zipfile,xml.etree.ElementTree as ET
from pathlib import Path

root=Path(sys.argv[1])
for ext,part in [('docx','word/document.xml'),('xlsx','xl/workbook.xml'),('pptx','ppt/presentation.xml')]:
    with zipfile.ZipFile(root/f'blank.{ext}') as archive:
        assert part in archive.namelist() and '[Content_Types].xml' in archive.namelist()
        assert not any('vba' in name.lower() for name in archive.namelist())
        for name in archive.namelist():
            if name.endswith(('.xml','.rels')):
                tree=ET.fromstring(archive.read(name))
                assert not any(node.attrib.get('TargetMode')=='External' for node in tree.iter())
        if ext=='xlsx':assert len(ET.fromstring(archive.read(part)).findall('.//{*}sheet'))==1
        if ext=='pptx':assert len(ET.fromstring(archive.read(part)).findall('.//{*}sldId'))==1
print('Passed blank Office package XML, worksheet/slide and no-macro/no-external-link checks')
