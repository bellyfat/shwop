from setuptools import setup
from pip.req import parse_requirements
from pip.download import PipSession


setup(
	name='schwapp',
	version='0.1',
	packages=['schwapp'],
	py_modules=['__main__'],
	python_requires='>3.5.0',
    install_requires=[str(ir.req) for ir in parse_requirements('requirements.txt', session=PipSession())],
	entry_points='''
	[console_scripts]
	schwapp=schwapp.__main__:main
	'''
)
